`timescale 1ns / 1ps

module util_cpack2_timestamp #(
  parameter NUM_OF_CHANNELS = 4,
  parameter SAMPLES_PER_CHANNEL = 1,
  parameter SAMPLE_DATA_WIDTH = 16
) (
    // ADC clock
    input adc_clk,

    // DMA clock
    input dma_clk,

    // Register-map/processor clock for debug/status output
    input up_clk,

    // Timestamp to stamp data stream with every timestamp_every blocks, in ADC clock domain
    input [63:0] timestamp,

    /*
    ** How many NUM_OF_CHANNELS * SAMPLES_PER_CHANNEL * SAMPLE_DATA_WIDTH blocks to expect between timestamp insertions, in DMA clock domain
    ** Depending on the number of enabled channels a block may represent a different number of samples.
    ** For example when NUM_OF_CHANNELS = 4 and SAMPLES_PER_CHANNEL = 1:
    **  With 4 channels enabled, a block consists of one sample for each channel.
    **  With 3 channels enabled, a block consists of one sample for each channel, with one to thre leftover samples.
    **      It takes 3 blocks, yielding 4 samples per channel to get the least significant channel back in the least significant bit of the block
    **      Timestamping here should ideally be set to a multiple of 3.
    **  With 2 channels enabled, a block consists of two samples for each channel.
    **  With 1 channel enabled, a block consists of four samples for each channel.
    */
    input [31:0] timestamp_every,

    // FIFO input
    input packed_fifo_wr_en,
    output packed_fifo_wr_overflow,
    input packed_fifo_wr_sync,
    input [NUM_OF_CHANNELS*SAMPLE_DATA_WIDTH*SAMPLES_PER_CHANNEL-1:0] packed_fifo_wr_data,

    // FIFO output
    output packed_timestamped_fifo_wr_en,
    input packed_timestamped_fifo_wr_overflow,
    output packed_timestamped_fifo_wr_sync,
    output [NUM_OF_CHANNELS*SAMPLE_DATA_WIDTH*SAMPLES_PER_CHANNEL-1:0] packed_timestamped_fifo_wr_data,

    // Debug/status output in DMA clock domain. Page is selected by
    // timestamp_every[31:28]; timestamp logic uses only timestamp_every[27:0].
    output [31:0] debug_status
);
    localparam SAMPLE_WIDTH = NUM_OF_CHANNELS*SAMPLE_DATA_WIDTH*SAMPLES_PER_CHANNEL;

    // FIFO write signals
    wire fifo_wr_rst_busy;
    wire fifo_wr_full;
    wire [(1 + 64 + SAMPLE_WIDTH)-1:0] fifo_wr_data;
    wire fifo_wr_en;

    // FIFO read signals
    wire fifo_rd_rst_busy;
    wire fifo_rd_empty;
    wire [(1 + 64 + SAMPLE_WIDTH)-1:0] fifo_rd_data;
    wire fifo_rd_en;

    // ADC -> DMA FIFO
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"),
        .FIFO_READ_LATENCY(0), // No output register stages, required for FWFT
        .FIFO_WRITE_DEPTH(16), // FIFO depth is 16 entries (xpm minimum)
        .READ_DATA_WIDTH(1+64+SAMPLE_WIDTH), // sync + timestamp + channel data
        .READ_MODE("fwft"), // First word fall though, such that first data is presented on output before empty is cleared
        .SIM_ASSERT_CHK(1), // Enable simulation messages - report misuse
        .USE_ADV_FEATURES("0000"), // Disable all advanced features
        .WRITE_DATA_WIDTH(1+64+SAMPLE_WIDTH) // sync + timestamp + channel data
    )
    fifo (
        .wr_clk(adc_clk),
        .rst('b0), // Unused reset input, syncronous to wr_clk
        .wr_rst_busy(fifo_wr_rst_busy), // If high wr_en should not be asserted
        .wr_en(fifo_wr_en),
        .din(fifo_wr_data),
        .full(fifo_wr_full),

        .rd_clk(dma_clk),
        .rd_rst_busy(fifo_rd_rst_busy), // If high rd_en should not be asserted
        .empty(fifo_rd_empty),
        .rd_en(fifo_rd_en),
        .dout(fifo_rd_data),

        .sleep('b0)
    );

    // Calculate when a fifo write is possible, aka fifo isn't busy and isn't full
    wire fifo_wr_possible;
    assign fifo_wr_possible = !fifo_wr_rst_busy && !fifo_wr_full;

    // Calculate when a fifo read is possible
    wire fifo_rd_possible;
    assign fifo_rd_possible = !fifo_rd_rst_busy && !fifo_rd_empty;

    // Combine write data - sync signal + 64-bit timestamp + samples
    assign fifo_wr_data = {packed_fifo_wr_sync, timestamp, packed_fifo_wr_data};

    // Calculate fifo write enable - write if space available and data is valid
    assign fifo_wr_en = fifo_wr_possible && packed_fifo_wr_en;

    // Split read data
    wire [63:0] fifo_data_timestamp_dma;
    wire fifo_data_sync_dma;
    wire [SAMPLE_WIDTH-1:0] fifo_data_dma;
    assign fifo_data_sync_dma = fifo_rd_data[SAMPLE_WIDTH+64];
    assign fifo_data_timestamp_dma = fifo_rd_data[SAMPLE_WIDTH +: 64];
    assign fifo_data_dma = fifo_rd_data[0 +: SAMPLE_WIDTH];

    wire [3:0] debug_page;
    wire [31:0] timestamp_every_effective;
    assign debug_page = timestamp_every[31:28];
    assign timestamp_every_effective = {4'b0000, timestamp_every[27:0]};

    // Timestamp block counter, incremented on each input
    // Reset when reaches or exceeds timestamp_every input
    reg [31:0] timestamp_counter = 'h0;

    // Define signal for timestamp enabled / output required
    wire timestamp_en;
    assign timestamp_en = (timestamp_every_effective != 0);
    wire timestamp_req;
    reg timestamp_pending_sample = 'b0;
    assign timestamp_req = timestamp_en && !timestamp_pending_sample &&
                           ((timestamp_counter == 0) || (timestamp_counter >= timestamp_every_effective));

    // The ADI fifo_wr interface reports backpressure as a delayed overflow/NACK.
    // Pulse each output word once, wait for the delayed NACK to become visible,
    // then either retry the same word or commit it and advance the RX cadence.
    localparam OUT_IDLE   = 2'd0;
    localparam OUT_SETTLE = 2'd1;
    localparam OUT_CHECK  = 2'd2;

    reg [1:0] output_state = OUT_IDLE;
    reg pending_is_sample = 'b0;
    reg pending_is_timestamp = 'b0;
    reg pending_sample_after_timestamp = 'b0;
    reg pending_sync = 'b0;
    reg [SAMPLE_WIDTH-1:0] pending_data = 'h0;

    wire output_accept;
    wire output_retry;
    assign output_accept = (output_state == OUT_CHECK) && !packed_timestamped_fifo_wr_overflow;
    assign output_retry = (output_state == OUT_CHECK) && packed_timestamped_fifo_wr_overflow;

    // Pop the input FIFO only after the downstream DMA has accepted a sample.
    // Timestamp words describe the FWFT sample and do not consume it.
    assign fifo_rd_en = output_accept && pending_is_sample;

    // FIFO output registers
    reg packed_timestamped_fifo_wr_en_reg = 'b0;
    reg packed_timestamped_fifo_wr_sync_reg = 'b0;
    reg [NUM_OF_CHANNELS*SAMPLE_DATA_WIDTH*SAMPLES_PER_CHANNEL-1:0] packed_timestamped_fifo_wr_data_reg = 'h0;

    reg [31:0] downstream_overflow_count = 'h0;
    reg [31:0] timestamp_insert_count = 'h0;
    reg [31:0] dropped_timestamped_block_count = 'h0;
    reg [31:0] last_timestamp_low = 'h0;
    reg [31:0] timestamp_every_latched = 'h0;
    reg [31:0] sample_output_count = 'h0;
    reg [31:0] fifo_read_stall_count = 'h0;
    reg downstream_overflow_sticky = 'b0;

    // Manage DMA-side output, timestamp cadence, and accepted-output counters.
    always @(posedge dma_clk) begin
        packed_timestamped_fifo_wr_en_reg <= 'b0;
        packed_timestamped_fifo_wr_sync_reg <= 'b0;
        packed_timestamped_fifo_wr_data_reg <= 'h0;
        timestamp_every_latched <= timestamp_every_effective;

        if (!timestamp_en) begin
            timestamp_counter <= 0;
            timestamp_pending_sample <= 'b0;
        end

        if (packed_timestamped_fifo_wr_overflow) begin
            downstream_overflow_count <= downstream_overflow_count + 1;
            downstream_overflow_sticky <= 'b1;
        end

        case (output_state)
            OUT_IDLE: begin
                if (fifo_rd_possible) begin
                    if (timestamp_req) begin
                        pending_data <= fifo_data_timestamp_dma;
                        pending_sync <= fifo_data_sync_dma;
                        pending_is_sample <= 'b0;
                        pending_is_timestamp <= 'b1;
                        pending_sample_after_timestamp <= 'b0;
                        packed_timestamped_fifo_wr_data_reg <= fifo_data_timestamp_dma;
                        packed_timestamped_fifo_wr_sync_reg <= fifo_data_sync_dma;
                    end else begin
                        pending_data <= fifo_data_dma;
                        pending_sync <= timestamp_en ? 'b0 : fifo_data_sync_dma;
                        pending_is_sample <= 'b1;
                        pending_is_timestamp <= 'b0;
                        pending_sample_after_timestamp <= timestamp_pending_sample;
                        packed_timestamped_fifo_wr_data_reg <= fifo_data_dma;
                        packed_timestamped_fifo_wr_sync_reg <= timestamp_en ? 'b0 : fifo_data_sync_dma;
                    end

                    packed_timestamped_fifo_wr_en_reg <= 'b1;
                    output_state <= OUT_SETTLE;
                end else if (timestamp_en) begin
                    fifo_read_stall_count <= fifo_read_stall_count + 1;
                end
            end

            OUT_SETTLE: begin
                output_state <= OUT_CHECK;
            end

            OUT_CHECK: begin
                if (output_retry) begin
                    packed_timestamped_fifo_wr_data_reg <= pending_data;
                    packed_timestamped_fifo_wr_sync_reg <= pending_sync;
                    packed_timestamped_fifo_wr_en_reg <= 'b1;
                    output_state <= OUT_SETTLE;

                    if (pending_is_timestamp || pending_sample_after_timestamp) begin
                        dropped_timestamped_block_count <= dropped_timestamped_block_count + 1;
                    end
                end else if (pending_is_timestamp) begin
                    timestamp_insert_count <= timestamp_insert_count + 1;
                    last_timestamp_low <= pending_data[31:0];
                    timestamp_pending_sample <= timestamp_en;

                    // The timestamp word was accepted; now issue the sample it
                    // describes. The FWFT FIFO is still presenting that sample.
                    pending_data <= fifo_data_dma;
                    pending_sync <= 'b0;
                    pending_is_sample <= 'b1;
                    pending_is_timestamp <= 'b0;
                    pending_sample_after_timestamp <= 'b1;
                    packed_timestamped_fifo_wr_data_reg <= fifo_data_dma;
                    packed_timestamped_fifo_wr_sync_reg <= 'b0;
                    packed_timestamped_fifo_wr_en_reg <= 'b1;
                    output_state <= OUT_SETTLE;
                end else begin
                    if (pending_is_sample) begin
                        sample_output_count <= sample_output_count + 1;

                        if (timestamp_en) begin
                            if (pending_sample_after_timestamp) begin
                                timestamp_pending_sample <= 'b0;
                                timestamp_counter <= 1;
                            end else begin
                                timestamp_counter <= timestamp_counter + 1;
                            end
                        end
                    end

                    output_state <= OUT_IDLE;
                end
            end

            default: begin
                output_state <= OUT_IDLE;
            end
        endcase
    end

    wire output_timestamp;
    wire output_sample;
    assign output_timestamp = output_accept && pending_is_timestamp;
    assign output_sample = output_accept && pending_is_sample;

    // Assign FIFO outputs
    assign packed_timestamped_fifo_wr_en = packed_timestamped_fifo_wr_en_reg;
    assign packed_timestamped_fifo_wr_sync = packed_timestamped_fifo_wr_sync_reg;
    assign packed_timestamped_fifo_wr_data = packed_timestamped_fifo_wr_data_reg;

    // Debug counters
    reg [31:0] cpack_fifo_overflow_count = 'h0;
    reg cpack_fifo_overflow_sticky = 'b0;

    always @(posedge adc_clk) begin
        if (packed_fifo_wr_en && !fifo_wr_possible) begin
            cpack_fifo_overflow_count <= cpack_fifo_overflow_count + 1;
            cpack_fifo_overflow_sticky <= 'b1;
        end
    end

    wire cpack_debug_sync_ready;
    wire [32:0] cpack_debug_status_dma;
    wire cpack_fifo_overflow_sticky_dma;
    wire [31:0] cpack_fifo_overflow_count_dma;

    cdc_sync_data_closed #(
        .NUM_BITS (33)
    ) cpack_debug_sync (
        .clk_in(adc_clk),
        .clk_out(dma_clk),
        .ready(cpack_debug_sync_ready),
        .enable('b1),
        .bits_in({cpack_fifo_overflow_sticky, cpack_fifo_overflow_count}),
        .valid(),
        .bits_out(cpack_debug_status_dma)
    );

    assign cpack_fifo_overflow_sticky_dma = cpack_debug_status_dma[32];
    assign cpack_fifo_overflow_count_dma = cpack_debug_status_dma[31:0];

    reg [31:0] debug_status_dma = 'h0;

    always @(posedge dma_clk) begin
        case (debug_page)
            4'h0: debug_status_dma <= {cpack_fifo_overflow_sticky_dma,
                                       downstream_overflow_sticky,
                                       packed_timestamped_fifo_wr_overflow,
                                       1'b0,
                                       fifo_rd_empty,
                                       timestamp_pending_sample,
                                       timestamp_req,
                                       timestamp_en,
                                       timestamp_insert_count[23:0]};
            4'h1: debug_status_dma <= cpack_fifo_overflow_count_dma;
            4'h2: debug_status_dma <= downstream_overflow_count;
            4'h3: debug_status_dma <= timestamp_insert_count;
            4'h4: debug_status_dma <= dropped_timestamped_block_count;
            4'h5: debug_status_dma <= last_timestamp_low;
            4'h6: debug_status_dma <= timestamp_every_latched;
            4'h7: debug_status_dma <= sample_output_count;
            4'h8: debug_status_dma <= fifo_read_stall_count;
            default: debug_status_dma <= 32'h43505854; // "CPXT"
        endcase
    end

    wire debug_status_sync_ready;
    cdc_sync_data_closed #(
        .NUM_BITS (32)
    ) debug_status_sync (
        .clk_in(dma_clk),
        .clk_out(up_clk),
        .ready(debug_status_sync_ready),
        .enable('b1),
        .bits_in(debug_status_dma),
        .valid(),
        .bits_out(debug_status)
    );

    // Pass downstream and local FIFO overflow up to cpack, crossing downstream
    // overflow into the ADC clock domain first.
    wire overflow_sync_ready;
    reg delayed_packed_timestamped_fifo_wr_overflow_reg = 'b0;
    wire curr_or_delayed_packed_timestamped_fifo_wr_overflow;
    wire downstream_overflow_adc;
    assign curr_or_delayed_packed_timestamped_fifo_wr_overflow = packed_timestamped_fifo_wr_overflow || delayed_packed_timestamped_fifo_wr_overflow_reg;

    cdc_sync_data_closed #(
        .NUM_BITS (1)
    ) overflow_sync (
        .clk_in(dma_clk),
        .clk_out(adc_clk),
        .ready(overflow_sync_ready),
        .enable('b1),
        .bits_in(curr_or_delayed_packed_timestamped_fifo_wr_overflow),
        .valid(),
        .bits_out(downstream_overflow_adc)
    );

    assign packed_fifo_wr_overflow = downstream_overflow_adc || !fifo_wr_possible;

    // Ensure overflows occuring while the syncronizer is busy are reported
    always @(posedge dma_clk) begin
        if (overflow_sync_ready) begin
            // Reset delayed value
            delayed_packed_timestamped_fifo_wr_overflow_reg <= 'b0;

        end else begin
            // Check for overflow while sycnronizer busy
            if (packed_timestamped_fifo_wr_overflow) begin
                // Hold delayed value such that it will be reported when the syncronizer is ready again
                delayed_packed_timestamped_fifo_wr_overflow_reg <= 'b1;
            end
        end
    end
endmodule

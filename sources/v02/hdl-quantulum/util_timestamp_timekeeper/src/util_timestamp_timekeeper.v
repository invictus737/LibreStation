`timescale 1ns / 1ps

module util_timestamp_timekeeper #(
    parameter TX_INTERP_FACTOR = 8,
    parameter RX_HOLD_SAMPLES = 2
) (
    // Radio sample clock domain
    input clk,

    // Synchronous reset in clk domain
    input reset,

    // RX user-sample cadence tick after the RX decimator.
    input rx_sample_tick,

    // TX raw converter valid tick, independent of RX DMA/activity.
    input tx_raw_sample_tick,

    // When asserted, derive one user-sample tick every TX_INTERP_FACTOR raw
    // ticks to match the TX interpolation filter.
    input tx_interpolation_active,

    // Monotonic sample/block timestamp in clk domain
    output [63:0] timestamp
);

    reg [63:0] timestamp_reg = 64'h0;
    reg [31:0] tx_interp_counter = 32'h0;
    reg [31:0] rx_hold_counter = 32'h0;

    wire tx_sample_tick;
    assign tx_sample_tick = tx_raw_sample_tick &&
                            (!tx_interpolation_active ||
                             (TX_INTERP_FACTOR <= 1) ||
                             (tx_interp_counter == (TX_INTERP_FACTOR - 1)));

    wire rx_alive;
    assign rx_alive = rx_sample_tick || (rx_hold_counter != 0);

    wire time_tick;
    assign time_tick = rx_sample_tick || (!rx_alive && tx_sample_tick);

    always @(posedge clk) begin
        if (reset) begin
            timestamp_reg <= 64'h0;
            tx_interp_counter <= 32'h0;
            rx_hold_counter <= 32'h0;
        end else begin
            if (tx_raw_sample_tick) begin
                if (!tx_interpolation_active || (TX_INTERP_FACTOR <= 1) || tx_sample_tick) begin
                    tx_interp_counter <= 32'h0;
                end else begin
                    tx_interp_counter <= tx_interp_counter + 32'h1;
                end
            end

            if (rx_sample_tick) begin
                rx_hold_counter <= RX_HOLD_SAMPLES;
            end else if (tx_sample_tick && (rx_hold_counter != 0)) begin
                rx_hold_counter <= rx_hold_counter - 32'h1;
            end

            if (time_tick) begin
                timestamp_reg <= timestamp_reg + 64'h1;
            end
        end
    end

    assign timestamp = timestamp_reg;

endmodule

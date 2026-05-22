`timescale 1ns / 1ps

module util_timestamp_timekeeper_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg rx_sample_tick = 1'b0;
    reg tx_raw_sample_tick = 1'b0;
    reg tx_interpolation_active = 1'b0;

    wire [63:0] timestamp;
    util_timestamp_timekeeper dut (
        .clk(clk),
        .reset(reset),
        .rx_sample_tick(rx_sample_tick),
        .tx_raw_sample_tick(tx_raw_sample_tick),
        .tx_interpolation_active(tx_interpolation_active),
        .timestamp(timestamp)
    );

    always #5 clk = ~clk;

    task tick_once;
        input rx;
        input tx;
        begin
            @(negedge clk);
            rx_sample_tick = rx;
            tx_raw_sample_tick = tx;
            @(negedge clk);
            rx_sample_tick = 1'b0;
            tx_raw_sample_tick = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;

        tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd1) begin
            $display("TX tick did not increment timestamp");
            $finish;
        end

        tick_once(1'b1, 1'b0);
        if (timestamp !== 64'd2) begin
            $display("RX tick did not increment timestamp");
            $finish;
        end

        tick_once(1'b1, 1'b1);
        if (timestamp !== 64'd3) begin
            $display("RX+TX same-cycle tick double counted");
            $finish;
        end

        // TX ticks are ignored briefly after RX activity, preventing mixed RX
        // and TX clocks from double-counting while RX is alive.
        tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd3) begin
            $display("TX fallback counted before RX hold expired");
            $finish;
        end

        tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd3) begin
            $display("TX fallback counted before second RX hold sample expired");
            $finish;
        end

        tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd4) begin
            $display("TX fallback did not resume after RX hold expired");
            $finish;
        end

        repeat (4) @(negedge clk);
        if (timestamp !== 64'd4) begin
            $display("Timestamp advanced without a cadence tick");
            $finish;
        end

        tx_interpolation_active = 1'b1;
        repeat (7) tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd4) begin
            $display("Interpolated TX tick advanced too early");
            $finish;
        end

        tick_once(1'b0, 1'b1);
        if (timestamp !== 64'd5) begin
            $display("Interpolated TX tick did not advance after factor raw ticks");
            $finish;
        end

        reset = 1'b1;
        @(negedge clk);
        reset = 1'b0;
        if (timestamp !== 64'd0) begin
            $display("Reset did not clear timestamp");
            $finish;
        end

        $display("util_timestamp_timekeeper_tb passed");
        $finish;
    end
endmodule

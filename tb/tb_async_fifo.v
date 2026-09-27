/*
 * tb_async_fifo.v -- self-checking dual-clock testbench (v2)
 *
 * v2 fix: stimulus is driven on NEGEDGE so wr_full/rd_empty are settled
 * values at the posedge sampling edge. (v1 checked full in the active
 * region right after the filling edge -> one write too many -> dropped
 * word -> scoreboard shift -> cascade.)
 *
 * Writer (100 MHz) sends an incrementing sequence with random gaps;
 * reader (71.4 MHz, unrelated clock) drains with random gaps.
 * Checks: data integrity (scoreboard), no overflow write, no underflow read.
 */
`timescale 1ns/1ps

module tb_async_fifo;
    localparam WIDTH = 8;
    localparam N     = 300;              // words transferred

    reg         wr_clk = 0, rd_clk = 0;
    reg         wr_rst_n = 0, rd_rst_n = 0;
    reg         wr_en = 0;
    reg  [WIDTH-1:0] wr_data = 0;
    wire        wr_full;
    reg         rd_en = 0;
    wire [WIDTH-1:0] rd_data;
    wire        rd_empty;

    integer errors = 0;
    integer wr_count = 0, rd_count = 0;
    integer gap_w = 0, gap_r = 0;
    reg verdict_done = 1'b0;

    async_fifo #(.WIDTH(WIDTH), .DEPTH(16)) dut (
        .wr_clk (wr_clk),   .wr_rst_n (wr_rst_n),
        .wr_en  (wr_en),    .wr_data  (wr_data),  .wr_full  (wr_full),
        .rd_clk (rd_clk),   .rd_rst_n (rd_rst_n),
        .rd_en  (rd_en),    .rd_data  (rd_data),  .rd_empty (rd_empty)
    );

    // unrelated clocks: 10 ns and 14 ns
    always #5  wr_clk = ~wr_clk;
    always #7  rd_clk = ~rd_clk;

    // -------- protocol checks (should never fire) --------
    always @(posedge wr_clk)
        if (wr_en && wr_full) begin
            $display("ERROR: write while FULL at t=%0t", $time);
            errors = errors + 1;
        end
    always @(posedge rd_clk)
        if (rd_en && rd_empty) begin
            $display("ERROR: read while EMPTY at t=%0t", $time);
            errors = errors + 1;
        end

    // -------- scoreboard: sample comb rd_data at the pop edge --------
    always @(posedge rd_clk) begin
        if (rd_en) begin
            if (rd_data !== rd_count[WIDTH-1:0]) begin
                $display("ERROR: data mismatch exp=%0d got=%0d at t=%0t",
                         rd_count[WIDTH-1:0], rd_data, $time);
                errors = errors + 1;
            end
            rd_count = rd_count + 1;
        end
    end

    // -------- writer (negedge-driven, full-safe) --------
    initial begin
        wr_en = 1'b0; wr_data = 0; gap_w = 0;
        wait (wr_rst_n);
        @(negedge wr_clk);
        while (wr_count < N) begin
            if (gap_w > 0) begin
                gap_w = gap_w - 1;
                wr_en = 1'b0;
                @(negedge wr_clk);
            end else if (!wr_full) begin
                wr_data = wr_count[WIDTH-1:0];
                wr_en   = 1'b1;
                wr_count = wr_count + 1;
                gap_w = $random & 3;
                @(negedge wr_clk);
                wr_en = 1'b0;
            end else begin
                wr_en = 1'b0;
                @(negedge wr_clk);
            end
        end
        wr_en = 1'b0;
    end

    // -------- reader (negedge-driven, empty-safe) --------
    initial begin
        rd_en = 1'b0; gap_r = 0;
        wait (rd_rst_n);
        @(negedge rd_clk);
        while (rd_count < N) begin
            if (gap_r > 0) begin
                gap_r = gap_r - 1;
                rd_en = 1'b0;
                @(negedge rd_clk);
            end else if (!rd_empty) begin
                rd_en = 1'b1;
                gap_r = $random & 3;
                @(negedge rd_clk);
                rd_en = 1'b0;
            end else begin
                rd_en = 1'b0;
                @(negedge rd_clk);
            end
        end
        rd_en = 1'b0;
    end

    // -------- reset + verdict --------
    initial begin
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (6) @(posedge rd_clk);
        rd_rst_n = 1;
    end

    always @(posedge rd_clk) begin
        if (rd_count == N && !verdict_done) begin
            verdict_done = 1'b1;
            repeat (5) @(posedge rd_clk);
            if (errors == 0)
                $display("TESTBENCH PASSED (%0d words, 0 errors)", N);
            else
                $display("TESTBENCH FAILED (%0d errors)", errors);
            $finish;
        end
    end

    // safety timeout
    initial begin
        #200000;
        $display("ERROR: TIMEOUT"); $finish;
    end
endmodule

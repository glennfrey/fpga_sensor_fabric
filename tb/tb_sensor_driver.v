/*
 * tb_sensor_driver.v -- persona-side driver for the M2 fabric TB
 * Lives in the persona clock domain. Pushes {rw,addr,wdata} into the port's
 * request FIFO; pops responses from the response FIFO. Comb-read sampling:
 * p_rd_data is sampled in the same cycle p_rd_en is asserted (before the
 * pop edge). Same deterministic sequence as tb_port_driver.
 */
module tb_sensor_driver #(
    parameter PORT_ID = 0,
    parameter BASE    = 32'h0000_0000,
    parameter NOPS    = 40
) (
    input  wire        pclk,
    input  wire        prst_n,
    output reg         p_wr_en,
    output reg  [64:0] p_wr_data,
    input  wire        p_wr_full,
    output reg         p_rd_en,
    input  wire [32:0] p_rd_data,
    input  wire        p_rd_empty,
    output reg         done,
    output integer     errors
);
    reg [31:0] exp_mem [0:31];
    reg        written [0:31];
    integer k, idx;
    reg [31:0] wdata;
    reg        rsp_err_s;
    reg [31:0] rsp_data_s;

    task automatic do_op(input bit rw, input [31:0] a, input [31:0] d,
                         input bit expect_err, input integer exp_idx);
    begin
        // push request
        @(negedge pclk);
        p_wr_data = {rw, a, d};
        p_wr_en   = 1'b1;
        @(negedge pclk);
        while (p_wr_full) @(negedge pclk);
        @(posedge pclk);            // fifo write accepted
        @(negedge pclk);
        p_wr_en = 1'b0;
        // wait response
        @(negedge pclk);
        while (p_rd_empty) @(negedge pclk);
        // comb read: sample in the SAME cycle rd_en is high
        rsp_err_s  = p_rd_data[32];
        rsp_data_s = p_rd_data[31:0];
        p_rd_en = 1'b1;
        @(posedge pclk);            // pop
        @(negedge pclk);
        p_rd_en = 1'b0;

        if (rsp_err_s !== expect_err) begin
            $display("ERROR P%0d: op rw=%b addr=%h err=%b (exp %b)", PORT_ID, rw, a, rsp_err_s, expect_err);
            errors = errors + 1;
        end else if (!rw && !rsp_err_s && rsp_data_s !== exp_mem[exp_idx]) begin
            $display("ERROR P%0d: read addr=%h exp=%h got=%h", PORT_ID, a, exp_mem[exp_idx], rsp_data_s);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        p_wr_en = 1'b0; p_wr_data = 65'h0;
        p_rd_en = 1'b0;
        done = 1'b0; errors = 0;
        for (k = 0; k < 32; k = k + 1) begin
            exp_mem[k] = 32'h0;
            written[k] = 1'b0;
        end
        @(posedge prst_n);
        repeat (4) @(posedge pclk);   // let synchronizers flush post-reset

        for (k = 0; k < NOPS; k = k + 1) begin
            idx = (k*7 + PORT_ID*5) % 32;
            if ((k % 3 == 2) && written[idx]) begin
                do_op(1'b1, BASE + idx*4, 32'h0, 1'b0, idx);
            end else begin
                wdata = (k * 32'h0101_0101) ^ (PORT_ID << 24) ^ idx;
                do_op(1'b0, BASE + idx*4, wdata, 1'b0, idx);
                exp_mem[idx] = wdata;
                written[idx] = 1'b1;
            end
        end

        do_op(1'b0, BASE + 32'h0000_0400, 32'hDEAD_BEEF, 1'b1, 0);
        do_op(1'b1, BASE + 32'h0000_0400, 32'h0,         1'b1, 0);

        done = 1'b1;
    end
endmodule

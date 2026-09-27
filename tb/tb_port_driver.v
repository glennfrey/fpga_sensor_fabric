/*
 * tb_port_driver.v -- deterministic request generator / scoreboard (per port)
 * Each port owns a disjoint 32-word region of the shared axilite_s memory
 * (BASE .. BASE + 0x7C), so ports race on the crossbar but never on data.
 * Sequence is deterministic: a read is issued only for words previously
 * written by THIS port. Ends with two OOB transactions that must return
 * rsp_err (DECERR from the slave).
 *
 * Handshake protocol (v2 fix): req_valid is sampled TOGETHER with
 * req_ready at a posedge; req_valid is dropped the negedge right after
 * the accept. The v1 loop sampled ready at negedges one cycle late,
 * which left req_valid asserted while the port re-entered IDLE and
 * caused a duplicate accept.
 */
module tb_port_driver #(
    parameter PORT_ID = 0,
    parameter BASE    = 32'h0000_0000,
    parameter NOPS    = 40
) (
    input  wire        clk,
    input  wire        rst_n,
    output reg         req_valid,
    input  wire        req_ready,
    output reg         req_rw,
    output reg  [31:0] req_addr,
    output reg  [31:0] req_wdata,
    input  wire        rsp_valid,
    input  wire [31:0] rsp_rdata,
    input  wire        rsp_err,
    output reg         done,
    output integer     errors
);
    reg [31:0] exp_mem [0:31];
    reg        written [0:31];
    integer k, idx;
    reg [31:0] wdata;

    task automatic do_op(input bit rw, input [31:0] a, input [31:0] d,
                         input bit expect_err, input integer exp_idx);
    begin
        // issue: hold valid until the posedge where valid && ready
        @(negedge clk);
        req_rw    = rw;
        req_addr  = a;
        req_wdata = d;
        req_valid = 1'b1;
        @(posedge clk);
        while (!req_ready) @(posedge clk);   // accept at THIS posedge
        @(negedge clk);
        req_valid = 1'b0;                    // drop immediately: no re-accept

        // wait response (valid + data stable from the previous NBA update)
        @(posedge clk);
        while (!rsp_valid) @(posedge clk);

        if (rsp_err !== expect_err) begin
            $display("ERROR P%0d: op rw=%b addr=%h err=%b (exp %b)", PORT_ID, rw, a, rsp_err, expect_err);
            errors = errors + 1;
        end else if (rw && !rsp_err && rsp_rdata !== exp_mem[exp_idx]) begin
            $display("ERROR P%0d: read addr=%h exp=%h got=%h", PORT_ID, a, exp_mem[exp_idx], rsp_rdata);
            errors = errors + 1;
        end
        @(negedge clk);
    end
    endtask

    initial begin
        req_valid = 1'b0; req_rw = 1'b0;
        req_addr = 32'h0; req_wdata = 32'h0;
        done = 1'b0; errors = 0;
        for (k = 0; k < 32; k = k + 1) begin
            exp_mem[k] = 32'h0;
            written[k] = 1'b0;
        end
        @(posedge rst_n);
        repeat (2) @(posedge clk);

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

        // out-of-bounds: must raise DECERR
        do_op(1'b0, BASE + 32'h0000_0400, 32'hDEAD_BEEF, 1'b1, 0);
        do_op(1'b1, BASE + 32'h0000_0400, 32'h0,         1'b1, 0);

        done = 1'b1;
    end
endmodule

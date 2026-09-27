/*
 * tb_crossbar.v -- 3-port crossbar + fixed axilite_s sink, self-checking
 * Each port: 40 deterministic ops over its own 32-word region + 2 OOB ops.
 * Expect: 0 mismatches, 0 protocol errors, TESTBENCH PASSED.
 */
`timescale 1ns/1ps

module tb_crossbar;
    localparam N = 3;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // upstream request/response wires
    wire [N-1:0]       req_valid, req_ready, req_rw, rsp_valid, rsp_err, done;
    wire [N*32-1:0]    req_addr, req_wdata, rsp_rdata;
    integer e0, e1, e2;

    // downstream AXI-Lite wires (declared BEFORE the DUT that drives them)
    wire awvalid, awready, wvalid, wready, bvalid, bready;
    wire arvalid, arready, rvalid, rready;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [1:0]  bresp, rresp;

    axil_crossbar #(.N(N)) dut (
        .aclk        (clk),
        .aresetn     (rst_n),
        .in_req_valid(req_valid),
        .in_req_ready(req_ready),
        .in_req_rw   (req_rw),
        .in_req_addr (req_addr),
        .in_req_wdata(req_wdata),
        .out_rsp_valid(rsp_valid),
        .out_rsp_rdata(rsp_rdata),
        .out_rsp_err (rsp_err),
        .s_awvalid   (awvalid), .s_awready(awready), .s_awaddr(awaddr),
        .s_wvalid    (wvalid),  .s_wready (wready),  .s_wdata (wdata),
        .s_bvalid    (bvalid),  .s_bready (bready),  .s_bresp (bresp),
        .s_arvalid   (arvalid), .s_arready(arready), .s_araddr(araddr),
        .s_rvalid    (rvalid),  .s_rready (rready),  .s_rdata (rdata),
        .s_rresp     (rresp)
    );

    axilite_s sink (
        .s_axi_aclk   (clk),      .s_axi_aresetn(rst_n),
        .s_axi_awvalid(awvalid),  .s_axi_awready(awready), .s_axi_awaddr (awaddr),
        .s_axi_wvalid (wvalid),   .s_axi_wready (wready),  .s_axi_wdata  (wdata),
        .s_axi_bvalid (bvalid),   .s_axi_bready (bready),  .s_axi_bresp  (bresp),
        .s_axi_arvalid(arvalid),  .s_axi_arready(arready), .s_axi_araddr (araddr),
        .s_axi_rvalid (rvalid),   .s_axi_rready (rready),  .s_axi_rdata  (rdata),
        .s_axi_rresp  (rresp)
    );

    tb_port_driver #(.PORT_ID(0), .BASE(32'h0000_0000)) p0 (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid[0]), .req_ready(req_ready[0]), .req_rw(req_rw[0]),
        .req_addr(req_addr[0*32 +: 32]), .req_wdata(req_wdata[0*32 +: 32]),
        .rsp_valid(rsp_valid[0]), .rsp_rdata(rsp_rdata[0*32 +: 32]), .rsp_err(rsp_err[0]),
        .done(done[0]), .errors(e0));
    tb_port_driver #(.PORT_ID(1), .BASE(32'h0000_0080)) p1 (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid[1]), .req_ready(req_ready[1]), .req_rw(req_rw[1]),
        .req_addr(req_addr[1*32 +: 32]), .req_wdata(req_wdata[1*32 +: 32]),
        .rsp_valid(rsp_valid[1]), .rsp_rdata(rsp_rdata[1*32 +: 32]), .rsp_err(rsp_err[1]),
        .done(done[1]), .errors(e1));
    tb_port_driver #(.PORT_ID(2), .BASE(32'h0000_0100)) p2 (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid[2]), .req_ready(req_ready[2]), .req_rw(req_rw[2]),
        .req_addr(req_addr[2*32 +: 32]), .req_wdata(req_wdata[2*32 +: 32]),
        .rsp_valid(rsp_valid[2]), .rsp_rdata(rsp_rdata[2*32 +: 32]), .rsp_err(rsp_err[2]),
        .done(done[2]), .errors(e2));

    initial begin
        $dumpfile("build/tb_crossbar.vcd"); $dumpvars(0, tb_crossbar);
        repeat (4) @(posedge clk);
        rst_n = 1;
        wait (&done);
        repeat (5) @(posedge clk);
        if (e0 + e1 + e2 == 0)
            $display("TESTBENCH PASSED (3 ports, %0d ops each + OOB)", 40);
        else
            $display("TESTBENCH FAILED (errors: %0d %0d %0d)", e0, e1, e2);
        $finish;
    end

    initial begin
        #500000;
        $display("ERROR: TIMEOUT"); $finish;
    end
endmodule

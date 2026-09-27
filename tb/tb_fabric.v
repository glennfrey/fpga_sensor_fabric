/*
 * tb_fabric.v -- M2: 3 persona domains (10/14/18 ns clocks) through
 * request/response async FIFOs into the crossbar + fixed axilite_s sink.
 * Expect: TESTBENCH PASSED.
 */
`timescale 1ns/1ps

module tb_fabric;
    localparam N = 3;
    localparam REQW = 65, RSPW = 33;

    reg aclk = 0;
    always #5 aclk = ~aclk;

    reg [N-1:0] pclk = 0, prst_n = 0, aresetn = 0;
    always #5  pclk[0] = ~pclk[0];   // 10 ns
    always #7  pclk[1] = ~pclk[1];   // 14 ns
    always #9  pclk[2] = ~pclk[2];   // 18 ns

    // persona-side wires
    wire [N-1:0]      p_wr_en, p_wr_full, p_rd_en, p_rd_empty, done;
    wire [N*REQW-1:0] p_wr_data;
    wire [N*RSPW-1:0] p_rd_data;
    integer e0, e1, e2;

    // downstream AXI-Lite wires (declared BEFORE the DUT that drives them)
    wire awvalid, awready, wvalid, wready, bvalid, bready;
    wire arvalid, arready, rvalid, rready;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [1:0]  bresp, rresp;

    sensor_fabric #(.N(N)) dut (
        .aclk   (aclk),     .aresetn(aresetn),
        .pclk   (pclk),     .prst_n (prst_n),
        .p_wr_en  (p_wr_en),   .p_wr_data(p_wr_data), .p_wr_full(p_wr_full),
        .p_rd_en  (p_rd_en),   .p_rd_data(p_rd_data), .p_rd_empty(p_rd_empty),
        .s_awvalid(awvalid), .s_awready(awready), .s_awaddr(awaddr),
        .s_wvalid (wvalid),  .s_wready (wready),  .s_wdata (wdata),
        .s_bvalid (bvalid),  .s_bready (bready),  .s_bresp (bresp),
        .s_arvalid(arvalid), .s_arready(arready), .s_araddr(araddr),
        .s_rvalid (rvalid),  .s_rready (rready),  .s_rdata (rdata),
        .s_rresp  (rresp)
    );

    axilite_s sink (
        .s_axi_aclk   (aclk),     .s_axi_aresetn(aresetn),
        .s_axi_awvalid(awvalid),  .s_axi_awready(awready), .s_axi_awaddr (awaddr),
        .s_axi_wvalid (wvalid),   .s_axi_wready (wready),  .s_axi_wdata  (wdata),
        .s_axi_bvalid (bvalid),   .s_axi_bready (bready),  .s_axi_bresp  (bresp),
        .s_axi_arvalid(arvalid),  .s_axi_arready(arready), .s_axi_araddr (araddr),
        .s_axi_rvalid (rvalid),   .s_axi_rready (rready),  .s_axi_rdata  (rdata),
        .s_axi_rresp  (rresp)
    );

    tb_sensor_driver #(.PORT_ID(0), .BASE(32'h0000_0000)) p0 (
        .pclk(pclk[0]), .prst_n(prst_n[0]),
        .p_wr_en(p_wr_en[0]), .p_wr_data(p_wr_data[0*REQW +: REQW]), .p_wr_full(p_wr_full[0]),
        .p_rd_en(p_rd_en[0]), .p_rd_data(p_rd_data[0*RSPW +: RSPW]), .p_rd_empty(p_rd_empty[0]),
        .done(done[0]), .errors(e0));
    tb_sensor_driver #(.PORT_ID(1), .BASE(32'h0000_0080)) p1 (
        .pclk(pclk[1]), .prst_n(prst_n[1]),
        .p_wr_en(p_wr_en[1]), .p_wr_data(p_wr_data[1*REQW +: REQW]), .p_wr_full(p_wr_full[1]),
        .p_rd_en(p_rd_en[1]), .p_rd_data(p_rd_data[1*RSPW +: RSPW]), .p_rd_empty(p_rd_empty[1]),
        .done(done[1]), .errors(e1));
    tb_sensor_driver #(.PORT_ID(2), .BASE(32'h0000_0100)) p2 (
        .pclk(pclk[2]), .prst_n(prst_n[2]),
        .p_wr_en(p_wr_en[2]), .p_wr_data(p_wr_data[2*REQW +: REQW]), .p_wr_full(p_wr_full[2]),
        .p_rd_en(p_rd_en[2]), .p_rd_data(p_rd_data[2*RSPW +: RSPW]), .p_rd_empty(p_rd_empty[2]),
        .done(done[2]), .errors(e2));

    initial begin
        $dumpfile("build/tb_fabric.vcd"); $dumpvars(0, tb_fabric);
        repeat (5) @(posedge aclk);
        aresetn = 1;
        prst_n  = 3'b111;
        wait (&done);
        repeat (5) @(posedge aclk);
        if (e0 + e1 + e2 == 0)
            $display("TESTBENCH PASSED (fabric M2: 3 GALS ports, %0d ops each + OOB)", 40);
        else
            $display("TESTBENCH FAILED (errors: %0d %0d %0d)", e0, e1, e2);
        $finish;
    end

    initial begin
        #1000000;
        $display("ERROR: TIMEOUT"); $finish;
    end
endmodule

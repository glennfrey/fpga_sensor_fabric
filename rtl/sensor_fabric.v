/*
 * sensor_fabric.v -- M2 integration: personas (own clocks) <-> crossbar
 *
 * Per port, two async FIFOs:
 *   req: persona clock -> system clock  (payload: {rw, addr, wdata} = 65b)
 *   rsp: system clock -> persona clock  (payload: {err, rdata}     = 33b)
 * One transaction in flight per port (crossbar arbiter guarantees the
 * system side); rsp FIFO depth 8 can never overflow under that contract.
 *
 * Sensor-side interface per port (driven by persona shim / TB driver):
 *   push req: p_wr_en / p_wr_data[64:0] / p_wr_full
 *   pop  rsp: p_rd_en / p_rd_data[32:0] / p_rd_empty   (comb read: sample
 *             p_rd_data in the same cycle p_rd_en is high, before the edge)
 */
module sensor_fabric #(
    parameter N      = 3,
    parameter IDXW   = (N <= 2) ? 1 : $clog2(N),
    parameter AXI_AW = 32,
    parameter AXI_DW = 32,
    parameter REQW   = 1 + AXI_AW + AXI_DW,   // 65
    parameter RSPW   = 1 + AXI_DW             // 33
) (
    input  wire                    aclk,
    input  wire                    aresetn,

    // per-persona clock/reset
    input  wire [N-1:0]            pclk,
    input  wire [N-1:0]            prst_n,

    // sensor side, per port
    input  wire [N-1:0]            p_wr_en,
    input  wire [N*REQW-1:0]       p_wr_data,
    output wire [N-1:0]            p_wr_full,
    input  wire [N-1:0]            p_rd_en,
    output wire [N*RSPW-1:0]       p_rd_data,
    output wire [N-1:0]            p_rd_empty,

    // downstream AXI-Lite slave (the shared sink)
    output wire                    s_awvalid,
    input  wire                    s_awready,
    output wire [AXI_AW-1:0]       s_awaddr,
    output wire                    s_wvalid,
    input  wire                    s_wready,
    output wire [AXI_DW-1:0]       s_wdata,
    input  wire                    s_bvalid,
    output wire                    s_bready,
    input  wire [1:0]              s_bresp,
    output wire                    s_arvalid,
    input  wire                    s_arready,
    output wire [AXI_AW-1:0]       s_araddr,
    input  wire                    s_rvalid,
    output wire                    s_rready,
    input  wire [AXI_DW-1:0]       s_rdata,
    input  wire [1:0]              s_rresp
);
    // request path (system side of req FIFOs)
    wire [N-1:0]        req_empty;
    wire [N*REQW-1:0]   req_data;
    wire [N-1:0]        req_pop;
    wire [N-1:0]        in_ready;

    // extracted per-port request fields
    wire [N-1:0]        req_rw_v;
    wire [N*AXI_AW-1:0] req_addr_v;
    wire [N*AXI_DW-1:0] req_wdata_v;

    // response path
    wire [N-1:0]        rsp_valid;
    wire [N*AXI_DW-1:0] rsp_rdata;
    wire [N-1:0]        rsp_err;
    wire [N-1:0]        rsp_full_unused;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_bridge
            // ---- request FIFO: persona -> system ----
            async_fifo #(.WIDTH(REQW), .DEPTH(8)) u_req_fifo (
                .wr_clk   (pclk[g]),
                .wr_rst_n (prst_n[g]),
                .wr_en    (p_wr_en[g]),
                .wr_data  (p_wr_data[g*REQW +: REQW]),
                .wr_full  (p_wr_full[g]),
                .rd_clk   (aclk),
                .rd_rst_n (aresetn),
                .rd_en    (req_pop[g]),
                .rd_data  (req_data[g*REQW +: REQW]),
                .rd_empty (req_empty[g])
            );

            assign req_pop[g] = in_ready[g] & ~req_empty[g];

            // payload layout: {rw, addr, wdata} with rw at the top
            assign req_rw_v[g]                     = req_data[g*REQW + REQW-1];
            assign req_addr_v[g*AXI_AW +: AXI_AW]  = req_data[g*REQW + AXI_DW +: AXI_AW];
            assign req_wdata_v[g*AXI_DW +: AXI_DW] = req_data[g*REQW +: AXI_DW];

            // ---- response FIFO: system -> persona ----
            async_fifo #(.WIDTH(RSPW), .DEPTH(8)) u_rsp_fifo (
                .wr_clk   (aclk),
                .wr_rst_n (aresetn),
                .wr_en    (rsp_valid[g]),
                .wr_data  ({rsp_err[g], rsp_rdata[g*AXI_DW +: AXI_DW]}),
                .wr_full  (rsp_full_unused[g]),
                .rd_clk   (pclk[g]),
                .rd_rst_n (prst_n[g]),
                .rd_en    (p_rd_en[g]),
                .rd_data  (p_rd_data[g*RSPW +: RSPW]),
                .rd_empty (p_rd_empty[g])
            );
        end
    endgenerate

    // never overflows: crossbar allows one transaction in flight per port
    wire _unused_full = &{1'b0, rsp_full_unused, 1'b0};

    axil_crossbar #(.N(N)) u_xbar (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .in_req_valid(~req_empty),
        .in_req_ready(in_ready),
        .in_req_rw   (req_rw_v),
        .in_req_addr (req_addr_v),
        .in_req_wdata(req_wdata_v),
        .out_rsp_valid(rsp_valid),
        .out_rsp_rdata(rsp_rdata),
        .out_rsp_err (rsp_err),
        .s_awvalid   (s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
        .s_wvalid    (s_wvalid),  .s_wready (s_wready),  .s_wdata (s_wdata),
        .s_bvalid    (s_bvalid),  .s_bready (s_bready),  .s_bresp (s_bresp),
        .s_arvalid   (s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
        .s_rvalid    (s_rvalid),  .s_rready (s_rready),  .s_rdata (s_rdata),
        .s_rresp     (s_rresp)
    );
endmodule

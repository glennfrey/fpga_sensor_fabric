/*
 * axil_crossbar.v -- N-port AXI4-Lite crossbar (M1: S=1 downstream sink)
 *
 * Upstream: one request interface per port (normally fed by the rd side of
 * an async_fifo in the sensor persona). Responses return as one-cycle
 * pulses; read data is valid when rsp_err == 0.
 *
 * Arbitration: round-robin over per-port busy; a fresh request is accepted
 * only when its port holds the grant, so at most one transaction is in
 * flight -> the granted master drives the single slave port directly.
 */
module axil_crossbar #(
    parameter N      = 3,
    parameter IDXW   = (N <= 2) ? 1 : $clog2(N),
    parameter AXI_AW = 32,
    parameter AXI_DW = 32
) (
    input  wire                 aclk,
    input  wire                 aresetn,

    input  wire [N-1:0]         in_req_valid,
    output wire [N-1:0]         in_req_ready,
    input  wire [N-1:0]         in_req_rw,
    input  wire [N*AXI_AW-1:0]  in_req_addr,
    input  wire [N*AXI_DW-1:0]  in_req_wdata,

    output wire [N-1:0]         out_rsp_valid,
    output wire [N*AXI_DW-1:0]  out_rsp_rdata,
    output wire [N-1:0]         out_rsp_err,

    output wire                 s_awvalid,
    input  wire                 s_awready,
    output wire [AXI_AW-1:0]    s_awaddr,
    output wire                 s_wvalid,
    input  wire                 s_wready,
    output wire [AXI_DW-1:0]    s_wdata,
    input  wire                 s_bvalid,
    output wire                 s_bready,
    input  wire [1:0]           s_bresp,
    output wire                 s_arvalid,
    input  wire                 s_arready,
    output wire [AXI_AW-1:0]    s_araddr,
    input  wire                 s_rvalid,
    output wire                 s_rready,
    input  wire [AXI_DW-1:0]    s_rdata,
    input  wire [1:0]           s_rresp
);
    wire [N-1:0] busy;

    // while any transaction is in flight only busy requests are visible,
    // which locks the grant; otherwise arbitrate among fresh requests
    wire [N-1:0] arb_req  = (|busy) ? busy : in_req_valid;
    wire [IDXW-1:0] grant;
    wire            grant_valid;
    wire            grant_done = |out_rsp_valid;

    rr_arbiter #(.N(N)) u_arbiter (
        .clk        (aclk),
        .rst_n      (aresetn),
        .req        (arb_req),
        .done       (grant_done),
        .grant      (grant),
        .grant_valid(grant_valid)
    );

    wire [N-1:0]          m_awvalid, m_wvalid, m_bready, m_arvalid, m_rready;
    wire [N*AXI_AW-1:0]   m_awaddr, m_araddr;
    wire [N*AXI_DW-1:0]   m_wdata;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_port
            /* verilator lint_off WIDTH */
            wire grant_g = grant_valid && (grant == g);
            /* verilator lint_on WIDTH */
            axil_mport #(.AXI_AW(AXI_AW), .AXI_DW(AXI_DW)) u_port (
                .clk          (aclk),
                .rst_n        (aresetn),
                .in_req_valid (in_req_valid[g]),
                .in_req_ready (in_req_ready[g]),
                .in_req_rw    (in_req_rw[g]),
                .in_req_addr  (in_req_addr[g*AXI_AW +: AXI_AW]),
                .in_req_wdata (in_req_wdata[g*AXI_DW +: AXI_DW]),
                .out_rsp_valid(out_rsp_valid[g]),
                .out_rsp_rdata(out_rsp_rdata[g*AXI_DW +: AXI_DW]),
                .out_rsp_err  (out_rsp_err[g]),
                .busy         (busy[g]),
                .grant_i      (grant_g),
                .m_awvalid    (m_awvalid[g]),
                .m_awready    (s_awready),
                .m_awaddr     (m_awaddr[g*AXI_AW +: AXI_AW]),
                .m_wvalid     (m_wvalid[g]),
                .m_wready     (s_wready),
                .m_wdata      (m_wdata[g*AXI_DW +: AXI_DW]),
                .m_bvalid     (s_bvalid),
                .m_bready     (m_bready[g]),
                .m_bresp      (s_bresp),
                .m_arvalid    (m_arvalid[g]),
                .m_arready    (s_arready),
                .m_araddr     (m_araddr[g*AXI_AW +: AXI_AW]),
                .m_rvalid     (s_rvalid),
                .m_rready     (m_rready[g]),
                .m_rdata      (s_rdata),
                .m_rresp      (s_rresp)
            );
        end
    endgenerate

    // single-slave mux: grant is stable for the whole transaction
    assign s_awvalid = m_awvalid[grant];
    assign s_awaddr  = m_awaddr[grant*AXI_AW +: AXI_AW];
    assign s_wvalid  = m_wvalid[grant];
    assign s_wdata   = m_wdata[grant*AXI_DW +: AXI_DW];
    assign s_bready  = m_bready[grant];
    assign s_arvalid = m_arvalid[grant];
    assign s_araddr  = m_araddr[grant*AXI_AW +: AXI_AW];
    assign s_rready  = m_rready[grant];
endmodule

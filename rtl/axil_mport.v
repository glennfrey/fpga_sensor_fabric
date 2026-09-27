/*
 * axil_mport.v -- AXI4-Lite master port (request FSM)
 *
 * Converts one {valid, rw, addr, wdata} request into AXI-Lite signaling
 * matching the axilite_s subset: AW then W then B (writes), AR then R
 * (reads); each channel held stable until its ready. Emits one response
 * pulse per request: read data + error flag (|resp).
 */
module axil_mport #(
    parameter AXI_AW = 32,
    parameter AXI_DW = 32
) (
    input  wire              clk,
    input  wire              rst_n,

    // upstream request (from sensor shim / async FIFO)
    input  wire              in_req_valid,
    output wire              in_req_ready,
    input  wire              in_req_rw,      // 1 = read, 0 = write
    input  wire [AXI_AW-1:0] in_req_addr,
    input  wire [AXI_DW-1:0] in_req_wdata,

    // response pulse (one cycle)
    output reg               out_rsp_valid,
    output reg  [AXI_DW-1:0] out_rsp_rdata,
    output reg               out_rsp_err,

    // busy to crossbar arbiter / grant back
    output reg               busy,
    input  wire              grant_i,

    // downstream AXI-Lite (crossbar slave mux)
    output wire              m_awvalid,
    input  wire              m_awready,
    output wire [AXI_AW-1:0] m_awaddr,
    output wire              m_wvalid,
    input  wire              m_wready,
    output wire [AXI_DW-1:0] m_wdata,
    input  wire              m_bvalid,
    output wire              m_bready,
    input  wire [1:0]        m_bresp,
    output wire              m_arvalid,
    input  wire              m_arready,
    output wire [AXI_AW-1:0] m_araddr,
    input  wire              m_rvalid,
    output wire              m_rready,
    input  wire [AXI_DW-1:0] m_rdata,
    input  wire [1:0]        m_rresp
);
    localparam [2:0] M_IDLE = 3'd0, M_WAW = 3'd1, M_WW = 3'd2,
                     M_WB  = 3'd3, M_RAR = 3'd4, M_RR  = 3'd5;

    reg [2:0]        state;
    reg [AXI_AW-1:0] r_addr;
    reg [AXI_DW-1:0] r_wdata;

    assign in_req_ready = (state == M_IDLE) & grant_i;

    assign m_awvalid = (state == M_WAW);
    assign m_awaddr  = r_addr;
    assign m_wvalid  = (state == M_WW);
    assign m_wdata   = r_wdata;
    assign m_bready  = (state == M_WB);
    assign m_arvalid = (state == M_RAR);
    assign m_araddr  = r_addr;
    assign m_rready  = (state == M_RR);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= M_IDLE;
            busy          <= 1'b0;
            out_rsp_valid <= 1'b0;
            out_rsp_rdata <= {AXI_DW{1'b0}};
            out_rsp_err   <= 1'b0;
            r_addr        <= {AXI_AW{1'b0}};
            r_wdata       <= {AXI_DW{1'b0}};
        end else begin
            out_rsp_valid <= 1'b0;
            case (state)
                M_IDLE: begin
                    if (in_req_valid && grant_i) begin
                        `ifdef DEBUG_XBAR
                        $display("[%0t] MPORT ACCEPT rw=%b addr=%h wdata=%h", $time, in_req_rw, in_req_addr, in_req_wdata);
                        `endif
                        r_addr <= in_req_addr;
                        r_wdata <= in_req_wdata;
                        busy   <= 1'b1;
                        state  <= in_req_rw ? M_RAR : M_WAW;
                    end
                end
                M_WAW: if (m_awready) state <= M_WW;
                M_WW:  if (m_wready)  state <= M_WB;
                M_WB: if (m_bvalid) begin
                    out_rsp_err   <= |m_bresp;
                    out_rsp_valid <= 1'b1;
                    busy          <= 1'b0;
                    state         <= M_IDLE;
                end
                M_RAR: if (m_arready) state <= M_RR;
                M_RR: if (m_rvalid) begin
                    out_rsp_rdata <= m_rdata;
                    out_rsp_err   <= |m_rresp;
                    out_rsp_valid <= 1'b1;
                    busy          <= 1'b0;
                    state         <= M_IDLE;
                end
                default: state <= M_IDLE;
            endcase
        end
    end
endmodule

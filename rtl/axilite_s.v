/*
 * axilite_s.v -- AXI4-Lite slave register file (reference sink, M1)
 *
 * Fixed version of the course-era axilite_s (original preserved in repo
 * history as the pre-lint baseline). Documented fixes:
 *   1. Word addressing: index = addr[8:2]; bounds = addr < 512 (128 words)
 *   2. Single memory write (redundant update_mem state removed)
 *   3. Nonblocking assignments only
 *   4. FSM and all channel registers fully reset
 *   5. Documented subset: W channel is serviced only AFTER AW is accepted
 *      (no W-before-AW reordering). Read latency ~3 cycles (dly counter).
 */
module axilite_s (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    input  wire [31:0] s_axi_wdata,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    output reg  [1:0]  s_axi_bresp,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    input  wire [31:0] s_axi_araddr,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp
);
    localparam integer WORDS = 128;
    localparam [3:0] ST_IDLE = 4'd0, ST_WADDR = 4'd1, ST_WDATA = 4'd2,
                     ST_WRESP = 4'd3, ST_RADDR = 4'd4, ST_RDATA = 4'd5;

    reg [3:0]  state;
    reg [31:0] waddr, raddr;
    reg [1:0]  dly;
    reg [31:0] mem [0:WORDS-1];

    wire [6:0] windex = waddr[8:2];
    wire [6:0] rindex = raddr[8:2];
    wire w_bounds_ok = (waddr < WORDS*4);
    wire r_bounds_ok = (raddr < WORDS*4);

    integer i;
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state         <= ST_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
            waddr <= 32'h0; raddr <= 32'h0; dly <= 2'b0;
            for (i = 0; i < WORDS; i = i + 1) mem[i] <= 32'h0;
        end else begin
            case (state)
                ST_IDLE: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b0;
                    if (s_axi_awvalid) begin
                        waddr         <= s_axi_awaddr;
                        s_axi_awready <= 1'b1;
                        state         <= ST_WADDR;
                    end else if (s_axi_arvalid) begin
                        raddr         <= s_axi_araddr;
                        s_axi_arready <= 1'b1;
                        dly           <= 2'b0;
                        state         <= ST_RADDR;
                    end
                end

                ST_WADDR: begin
                    s_axi_awready <= 1'b0;
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        state        <= ST_WDATA;
                    end
                end

                ST_WDATA: begin
                    s_axi_wready <= 1'b0;
                    `ifdef DEBUG_XBAR
                    $display("[%0t] SLAVE WR mem[%0d] <= %h (awaddr=%h)", $time, windex, s_axi_wdata, waddr);
                    `endif
                    if (w_bounds_ok) begin
                        mem[windex] <= s_axi_wdata;
                        s_axi_bresp <= 2'b00;
                    end else begin
                        s_axi_bresp <= 2'b11; // DECERR
                    end
                    s_axi_bvalid <= 1'b1;
                    state        <= ST_WRESP;
                end

                ST_WRESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                ST_RADDR: begin
                    s_axi_arready <= 1'b0;
                    state         <= ST_RDATA;
                end

                ST_RDATA: begin
                    if (dly < 2) begin
                        dly <= dly + 2'b1;      // documented read latency
                    end else if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;   // handshake complete
                        state        <= ST_IDLE;
                    end else begin
                        `ifdef DEBUG_XBAR
                        $display("[%0t] SLAVE RD mem[%0d] -> %h (araddr=%h)", $time, rindex, mem[rindex], raddr);
                        `endif
                        s_axi_rvalid <= 1'b1;
                        s_axi_rdata  <= r_bounds_ok ? mem[rindex] : 32'h0;
                        s_axi_rresp  <= r_bounds_ok ? 2'b00 : 2'b11; // DECERR
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // intentionally-unused address bits (verilator UNUSED idiom)
    wire _unused_ok = &{1'b0, waddr[31:9], waddr[1:0],
                              raddr[31:9], raddr[1:0], 1'b0};
endmodule

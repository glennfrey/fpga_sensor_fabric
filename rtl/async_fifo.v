/*
 * async_fifo.v -- dual-clock FIFO, Gray-coded pointers (Cummings-style)
 *
 * CDC structure (this module IS the CDC signoff target):
 *   - write pointer crosses to read domain  via cdc_sync_2ff (2 flops)
 *   - read pointer crosses to write domain  via cdc_sync_2ff (2 flops)
 *   - full/empty are REGISTERED in their own domains (never crossed raw)
 *   - memory is written in wr_clk domain, read combinationally in
 *     rd_clk domain (depth >= 4, power-of-two)
 *
 * Tools: iverilog -g2012, Verilator (-Wall clean), JasperGold CDC.
 */
module cdc_sync_2ff #(
    parameter WIDTH = 2
) (
    input  wire             dst_clk,
    input  wire             dst_rst_n,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    reg [WIDTH-1:0] meta;
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            meta <= {WIDTH{1'b0}};
            q    <= {WIDTH{1'b0}};
        end else begin
            meta <= d;
            q    <= meta;
        end
    end
endmodule


module async_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16,                    // power of two, >= 4
    parameter PTRW  = $clog2(DEPTH)          // binary pointer width
) (
    // ---- write domain ----
    input  wire             wr_clk,
    input  wire             wr_rst_n,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output reg              wr_full,
    // ---- read domain ----
    input  wire             rd_clk,
    input  wire             rd_rst_n,
    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output reg              rd_empty
);
    localparam GRAYW = PTRW + 1;             // Gray width incl. wrap bit

    // storage
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // pointers in binary + Gray form (one extra wrap bit)
    reg  [GRAYW-1:0] wr_ptr_bin,  wr_ptr_gray;
    reg  [GRAYW-1:0] rd_ptr_bin,  rd_ptr_gray;

    // pointers after crossing (synchronized into the OTHER domain)
    wire [GRAYW-1:0] rd_ptr_gray_wsync;      // rd -> wr domain
    wire [GRAYW-1:0] wr_ptr_gray_rsync;      // wr -> rd domain

    // -------------------------------------------------------------
    // Write clock domain
    // -------------------------------------------------------------
    wire wr_allow = wr_en & ~wr_full;

    wire [GRAYW-1:0] wr_bin_next  = wr_ptr_bin + {{(GRAYW-1){1'b0}}, wr_allow};
    wire [GRAYW-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    // full_next: write Gray-next == read Gray-sync with top-2 bits inverted
    wire [GRAYW-1:0] wr_full_cmp = {~rd_ptr_gray_wsync[GRAYW-1:GRAYW-2],
                                     rd_ptr_gray_wsync[GRAYW-3:0]};

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= {GRAYW{1'b0}};
            wr_ptr_gray <= {GRAYW{1'b0}};
            wr_full     <= 1'b0;
        end else begin
            wr_ptr_bin  <= wr_bin_next;
            wr_ptr_gray <= wr_gray_next;
            wr_full     <= (wr_gray_next == wr_full_cmp);
            if (wr_allow)
                mem[wr_ptr_bin[PTRW-1:0]] <= wr_data;
        end
    end

    cdc_sync_2ff #(.WIDTH(GRAYW)) u_sync_rd2wr (
        .dst_clk   (wr_clk),
        .dst_rst_n (wr_rst_n),
        .d         (rd_ptr_gray),
        .q         (rd_ptr_gray_wsync)
    );

    // -------------------------------------------------------------
    // Read clock domain
    // -------------------------------------------------------------
    wire rd_allow = rd_en & ~rd_empty;

    wire [GRAYW-1:0] rd_bin_next  = rd_ptr_bin + {{(GRAYW-1){1'b0}}, rd_allow};
    wire [GRAYW-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= {GRAYW{1'b0}};
            rd_ptr_gray <= {GRAYW{1'b0}};
            rd_empty    <= 1'b1;
        end else begin
            rd_ptr_bin  <= rd_bin_next;
            rd_ptr_gray <= rd_gray_next;
            rd_empty    <= (rd_gray_next == wr_ptr_gray_rsync);
        end
    end

    cdc_sync_2ff #(.WIDTH(GRAYW)) u_sync_wr2rd (
        .dst_clk   (rd_clk),
        .dst_rst_n (rd_rst_n),
        .d         (wr_ptr_gray),
        .q         (wr_ptr_gray_rsync)
    );

    // combinational read (registered-read variant noted in README)
    assign rd_data = mem[rd_ptr_bin[PTRW-1:0]];

endmodule

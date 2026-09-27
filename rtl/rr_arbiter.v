/*
 * rr_arbiter.v -- round-robin arbiter, rotating priority
 * Priority wraps from `base`; on `done` the pointer advances past the
 * granted index. Combinational grant from registered base (stable during
 * a transaction because the request vector is held by per-port busy).
 */
module rr_arbiter #(
    parameter N    = 3,
    parameter IDXW = (N <= 2) ? 1 : $clog2(N)
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [N-1:0]     req,
    input  wire             done,
    output reg  [IDXW-1:0]  grant,
    output wire             grant_valid
);
    reg [IDXW-1:0] base;

    // candidates at/after base first; wrap if none
    wire [N-1:0] mask = {N{1'b1}} << base;
    wire [N-1:0] cand = (|(req & mask)) ? (req & mask) : req;

    integer i;
    reg found;
    always @(*) begin
        grant = {IDXW{1'b0}};
        found = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (cand[i] && !found) begin
                /* verilator lint_off WIDTH */
                grant = i;
                /* verilator lint_on WIDTH */
                found = 1'b1;
            end
        end
    end

    assign grant_valid = |req;

    /* verilator lint_off WIDTH */
    localparam [IDXW-1:0] LAST = N - 1;
    /* verilator lint_on WIDTH */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base <= {IDXW{1'b0}};
        end else if (done) begin
            base <= (grant == LAST) ? {IDXW{1'b0}}
                                    : grant + {{(IDXW-1){1'b0}}, 1'b1};
        end
    end
endmodule

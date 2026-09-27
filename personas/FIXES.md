# Persona baseline — known issues & fix list (the lint findings arc)

Each file here is the ORIGINAL course-era code, unmodified, so the
findings -> fixes -> clean-report history can be real. Suggested commit
sequence: commit everything as `baseline:`, then one commit per fix with
the message prefix shown. The fixed AXI sink reference is `rtl/axilite_s.v`.

## axilite_s (AXI-1..AXI-5) — most severe first
- AXI-1  Byte-vs-word addressing: `mem[waddr]` uses the raw byte address as
         the index with `waddr < 128` bounds. Use `mem[waddr[8:2]]` with
         bounds `waddr < 512`. (Same for reads.)
- AXI-2  Double write: `mem[waddr] <= wdata` in BOTH `send_wdata_ack` and
         `update_mem`. Remove `update_mem`; write once in `send_wdata_ack`.
- AXI-3  Blocking assignment in clocked block: `s_axi_arready = 1'b0;` in
         `send_raddr_ack`. Change to `<=`.
- AXI-4  Duplicate `s_axi_rvalid <= 1'b0;` in `idle` (twice).
- AXI-5  Dead register: `next_state` declared, never used. Delete.
         Documented (not a bug): W-after-AW ordering subset; read latency
         from `count < 2`.

## spi_master / spi_slave (SPI-1..SPI-4)
- SPI-1  Mode-0 sampling edge violation: `mosi <= temp[count]` changes MOSI
         on `posedge sclk` while the slave samples on `posedge sclk`.
         Change the master bit-update block to `always @(negedge sclk)`.
- SPI-2  `int countc / int count` as 32-bit counters -> use `logic [3:0]`.
- SPI-3  Declaration-time initializers (`state = idle`, `temp = 12'h000`):
         FPGA-only idiom; rely on reset (SPI-4).
- SPI-4  `spi_slave` FSM/counters/temp have NO reset; only `done` is init'd,
         and only in `detect_start`. Add reset. Master `cs/mosi` reset too.
- Documented: no MISO (master->slave only) and derived `sclk` clock domain.

## i2c_master / i2c_Slave (I2C-0..I2C-4)
- I2C-0  SYNTAX (blocks compilation): `i2c_top` has a trailing empty port:
         `i2c_Slave slave (scl, clk, rst, sda, ack_errs, );` -- remove the
         trailing `, )` -> `ack_errs);` FIRST so lint can even run.
- I2C-1  Open-drain violation (master): comment says "release when sda_t=1"
         but code drives `1'b1`:
         `assign sda = (sda_en) ? ((sda_t == 0) ? 1'b0 : 1'b1) : 1'bz;`
         Fix: `assign sda = (sda_en && !sda_t) ? 1'b0 : 1'bz;`
- I2C-2  Same violation (slave): `(sda_en) ? sda_t : 1'bz` can drive 1.
         Fix: `assign sda = (sda_en && !sda_t) ? 1'b0 : 1'bz;`
- I2C-3  Unsynchronized CDC inputs (slave): `scl`/`sda` sampled directly in
         the `clk` domain (`scl_t <= scl`, shift registers). In the fabric
         these pins arrive from another domain -> sync or document the
         boundary FIFO as the synchronizer.
- I2C-4  Magic numbers tied to params: `count1 == 200/399/100` break if
         `i2c_freq` changes. Derive from `clk_count1`. `i2c_clk` unused.

## uarttx / uartrx (UART-1..UART-4)
- UART-1 `uartrx`: `state` is never reset (reset branch clears rxdata/
         counts/done only). Add `state <= idle;`. Also `uarttx` leaves
         `tx/donetx/din` unreset -> reset them.
- UART-2 `uarttx` declares `start` and `done` states the FSM never enters.
         Remove the dead enum values.
- UART-3 `integer count/counts` -> sized `logic` counters.
- UART-4 Async `rx` sampled by the `uclk` domain without a synchronizer.
         In the fabric the port async FIFO is the fix; document it.
         Documented: start-bit sampled at bit edge, not mid-bit.

## Single-clock FIFO (FIFO-1..FIFO-3) [add your fifo.v here]
- FIFO-1 No simultaneous read+write: `else if (wr) ... else if (rd)` drops
         a concurrent read. Restructure: independent `if (wr && !full)` /
         `if (rd && !empty)`; `cnt` holds when both fire.
- FIFO-2 `dout` is registered: valid the cycle AFTER `rd` -- document the
         read-latency-1 convention (same convention the fabric FIFOs use).
- FIFO-3 Declaration initializers; also reset is active-high here while the
         fabric uses active-low `rst_n` -- note at integration boundaries.

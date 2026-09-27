# fpga_sensor_fabric -- M1 building block: async FIFO (CDC core)

## Contents
    rtl/async_fifo.v      dual-clock FIFO, Gray pointers, 2-ff synchronizers
    tb/tb_async_fifo.v    self-checking TB (unrelated clocks, scoreboard)

## Run
    make sim     # iverilog: expect TESTBENCH PASSED (300 words)
    make lint    # verilator -Wall
    make all

## Why this module exists (CDC signoff target)
Every sensor port in the fabric crosses clock domains through one of these.
For JasperGold/CDC analysis, the structure to verify:
  1. rd_ptr_gray -> cdc_sync_2ff -> rd_ptr_gray_wsync  (rd domain to wr domain)
  2. wr_ptr_gray -> cdc_sync_2ff -> wr_ptr_gray_rsync  (wr domain to rd domain)
  3. full/empty registered in own domains; Gray code: adjacent values differ
     by 1 bit (no multi-bit CDC on pointer buses)
  4. mem written in wr_clk, read in rd_clk (depth>=4, power-of-two)

## Known limitations (document, don't hide)
  - combinational read (not BRAM-inferring); registered-read variant is a
    one-line change if P&R needs it
  - no write-count/read-count outputs (add when the crossbar needs them
    for credit-based flow control)
  - reset must be released long enough for both synchronizer chains to
    flush before traffic starts (TB: 4-6 cycles)

## M1 additions: AXI4-Lite crossbar + RR arbiter + fixed slave sink

    rtl/rr_arbiter.v    round-robin, rotating base, grant locked by busy
    rtl/axil_mport.v    per-port AXI-Lite master FSM (AW/W/B, AR/R)
    rtl/axil_crossbar.v N=3 ports -> 1 axilite_s sink; one transaction
                        in flight at a time (arbiter locks via busy)
    rtl/axilite_s.v     FIXED reference sink (see header for fix list)
    tb/tb_crossbar.v    3 ports x (40 ops + 2 OOB), disjoint regions,
                        self-checking scoreboard per port

## Run
    make sim        # crossbar TB: expect TESTBENCH PASSED
    make lint       # verilator -Wall on the crossbar hierarchy

## Integration notes (M2)
  - in_req_* is exactly what the async_fifo read side feeds:
        req_valid = ~rd_empty; pop on (req_valid & req_ready)
  - Read responses (out_rsp_*) currently terminate at the port; M2 adds a
    per-port return FIFO into the sensor shim (credit flow control TBD).
  - Slave subset intentionally documented in axilite_s.v header; the
    crossbar master matches it (AW before W, ready-held channels).

## M2: GALS integration (persona domains <-> system domain)
    rtl/sensor_fabric.v   per port: req async FIFO (persona->sys, 65b) +
                        rsp async FIFO (sys->persona, 33b); crossbar inside
    tb/tb_sensor_driver.v persona-domain driver (FIFO push/pop handshake)
    tb/tb_fabric.v        3 persona clocks (10/14/18 ns) + shared sink

    make sim_fabric     # expect TESTBENCH PASSED
    make lint_fabric

CDC note: each port now has TWO crossings (req out, rsp back) -> exactly
what JasperGold CDC should enumerate: 4 synchronizer chains per port
(2 per FIFO), Gray pointers, full/empty in own domains.

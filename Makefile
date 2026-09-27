IVERILOG  := iverilog
IVERILOG  += -DDEBUG_XBAR
VVP       := vvp
VERILATOR := verilator
RTL_XBAR  := rtl/axil_crossbar.v rtl/axil_mport.v rtl/rr_arbiter.v rtl/axilite_s.v
RTL_FIFO  := rtl/async_fifo.v
RTL_FABRIC:= rtl/sensor_fabric.v rtl/axil_crossbar.v rtl/axil_mport.v rtl/rr_arbiter.v rtl/axilite_s.v rtl/async_fifo.v

.PHONY: all sim sim_fifo sim_fabric lint lint_fifo lint_fabric clean
all: sim sim_fifo sim_fabric lint lint_fifo lint_fabric

sim: build/tb_xbar.vvp
	$(VVP) $< | tee build/sim_xbar.log
	grep -q "TESTBENCH PASSED" build/sim_xbar.log

sim_fifo: build/tb_fifo.vvp
	$(VVP) $< | tee build/sim_fifo.log
	grep -q "TESTBENCH PASSED" build/sim_fifo.log

sim_fabric: build/tb_fabric.vvp
	$(VVP) $< | tee build/sim_fabric.log
	grep -q "TESTBENCH PASSED" build/sim_fabric.log

build/tb_fabric.vvp: $(RTL_FABRIC) tb/tb_fabric.v tb/tb_sensor_driver.v | build
	$(IVERILOG) -g2012 -o $@ $^

lint_fabric: $(RTL_FABRIC)
	$(VERILATOR) --lint-only -Wall $^ --top-module sensor_fabric

build/tb_xbar.vvp: $(RTL_XBAR) tb/tb_crossbar.v tb/tb_port_driver.v | build
	$(IVERILOG) -g2012 -o $@ $^

build/tb_fifo.vvp: $(RTL_FIFO) tb/tb_async_fifo.v | build
	$(IVERILOG) -g2012 -o $@ $^

lint: $(RTL_XBAR)
	$(VERILATOR) --lint-only -Wall $^ --top-module axil_crossbar

lint_fifo: $(RTL_FIFO)
	$(VERILATOR) --lint-only -Wall $^ --top-module async_fifo

build:
	mkdir -p build

clean:
	rm -rf build

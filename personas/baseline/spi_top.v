`timescale 1ns / 1ps
// BASELINE (pre-lint, as pasted).
module spi_top (
input clk, rst, newd,
input [11:0] din,
output [11:0] dout,
output done
);

wire sclk, cs, mosi;

spi_master m1 (clk, newd, rst, din, sclk, cs, mosi);
spi_slave s1  (sclk, cs, mosi, dout, done);

endmodule

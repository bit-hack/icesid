/*
 * top_tb.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2020  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`timescale 1 ns / 100 ps
`default_nettype none

module top_tb;

	// Signals
	// -------

	reg clk = 1'b0;



	// Setup recording
	// ---------------

	initial begin
		$dumpfile("top_tb.vcd");
		$dumpvars(0,top_tb);
		# 20000000 $finish;
	end

	always #10 clk <= !clk;

    wire scl_led;
    wire sda_btn;

	// DUT
	// ---

	top dut_I (
		.sys_clk   (clk),
		.scl_led   (),
		.sda_btn   (),
		.i2s_sclk  (),
		.i2s_din   (),
		.i2s_dout  (),
		.i2s_lrclk ()
	);

	pullup(scl_led);
	pullup(sda_btn);

endmodule // top_tb

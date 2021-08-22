/*
 * codec_fix_tb.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2020  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none
`timescale 1ns/1ps

module i2s_master_tb;
	// Setup recording
	// ---------------

	initial begin
		$dumpfile("i2s_master_tb.vcd");
		$dumpvars(0,i2s_master_tb);
		# 40000 $finish;
	end

    // Signals
	reg clk = 0;
	reg [15:0] smp;
    wire bck, lck, din, sck;

	always #42 clk <= !clk; // roughly 24MHz

    // Initial values
	initial begin
	    smp = 16'h55AA;
	end

    // Device Under Test
	i2s_master dut_I (
	    .CLK(clk),
	    .SMP(smp),
	    .SCK(sck),
	    .BCK(bck),
	    .DIN(din),
	    .LCK(lck)
	);

endmodule // i2c_state_machine_tb

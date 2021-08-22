/*
 * codec_fix_tb.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2020  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module i2c_state_machine_tb;

	// Signals
	// -------

	reg clk = 1'b0;
	reg rst = 1'b1;


	// Setup recording
	// ---------------

	initial begin
		$dumpfile("i2c_state_machine_tb.vcd");
		$dumpvars(0,i2c_state_machine_tb);
		# 20000000 $finish;
	end

	always #10 clk <= !clk;

	initial begin
		#200 rst = 0;
	end

    wire scl_led;
    wire sda_btn;


	// DUT
	// ---

	i2c_state_machine dut_I (
	    .scl_led(scl_led),
	    .sda_btn(sda_btn),
		.led (1'b0),
		.clk (clk),
		.rst (rst)
	);

	pullup(scl_led);
	pullup(sda_btn);

endmodule // i2c_state_machine_tb

/*
 * sid_bus_if.v
 *
 * vim: ts=4 sw=4
 *
 * Interface to the 6510 CPU bus
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-S-2.0
 */
 `default_nettype none

module sid_bus_if #(
	parameter integer AW = 5,

	// auto-set
	parameter integer AL = AW-1
)(
	// Pads
	inout  wire [AL:0] pad_a,
	inout  wire [ 7:0] pad_d,
	inout  wire        pad_r_wn,
	inout  wire        pad_csn,
	inout  wire        pad_phi2,

	// Internal bus
	output wire [AL:0] bus_addr,
	input  wire [ 7:0] bus_rdata,
	output wire [ 7:0] bus_wdata,
	output wire        bus_we,

	output wire        clk_en,

	// Clock
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// "Control" signals
	wire [AL:0] if_a;
	wire        if_r_wn;
	wire        if_csn;

	wire [ 7:0] if_d_i;
	wire [ 7:0] if_d_o = bus_rdata;
	wire        if_d_oe;

	// PHI2
	wire        phi2_iob;
	reg   [2:0] phi2_state;
	reg         phi2_rise;
	reg         phi2_fall;


	// PHY
	// ---

	// The debounce on inputs has several roles.
	//
	//  - Solve metastable sampling in this block (although shouldn't be an
	//    issue anyway since signals are stable when used)
	//
	//  - Prevent any glitch / noise to make it through
	//
	//  - Delay the signals by 4 cycles meaning we use the values that were
	//    on the bus slightly _before_ the falling edge, where they are stable

	sid_bus_if_debounce #(
		.BIDIR(0)
	) phy_a_I[AL:0] (
		.pad (pad_a),
		.i   (if_a),
		.clk (clk),
		.rst (rst)
	);

	sid_bus_if_debounce #(
		.BIDIR(0)
	) phy_ctrl_I[1:0] (
		.pad ({pad_r_wn, pad_csn}),
		.i   ({ if_r_wn,  if_csn}),
		.clk (clk),
		.rst (rst)
	);

	sid_bus_if_debounce #(
		.BIDIR(1)
	) phy_d_I[7:0] (
		.pad (pad_d),
		.i   (if_d_i),
		.o   (if_d_o),
		.oe  (if_d_oe),
		.clk (clk),
		.rst (rst)
	);


	// Clock is special
	//
	//  - We want to minimize the delay on falling edge detect
	//  - The driver is good at driving the line low, but sucks at
	//    driving it high.
	//
	//  => So we use an assymetric debounce where falling edge detect
	//     is near immediate, but rising edge takes time.

	SB_IO #(
		.PIN_TYPE    (6'b0000_00),   // Reg input, No output
		.PULLUP      (1'b0),
		.IO_STANDARD ("SB_LVCMOS")
	) phi2_iob_I (
		.PACKAGE_PIN (pad_phi2),
		.INPUT_CLK   (clk),
		.D_IN_0      (phi2_iob)
	);

	always @(posedge clk or posedge rst)
		if (rst)
			{ phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b000 };
		else
			casez ({phi2_iob, phi2_state})
				// Stay at 0
				4'b0000: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b000 };

				// Stay at 1
				4'b1111: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b111 };

				// Falling edge (on first detected 0)
				4'b0zzz: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b1, 3'b000 };

				// Rising edge
				4'b1000: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b001 };
				4'b1001: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b010 };
				4'b1010: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b011 };
				4'b1011: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b100 };
				4'b1100: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b101 };
				4'b1101: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b110 };
				4'b1110: { phi2_rise, phi2_fall, phi2_state } <= { 1'b1, 1'b0, 3'b111 };

				// Catch all
				default: { phi2_rise, phi2_fall, phi2_state } <= { 1'b0, 1'b0, 3'b000 };
			endcase


	// Bus cycles
	// ----------

	assign clk_en = phi2_fall;

	assign bus_addr  = if_a;
	assign bus_wdata = if_d_i;
	assign bus_we    = phi2_fall & ~if_r_wn & ~if_csn;
	assign if_d_oe   = 1'b0; // if_r_wn & ~if_csn & phi2_iob;

endmodule // sid_bus_if


module sid_bus_if_debounce #(
	parameter integer BIDIR = 0
)(
	inout  wire pad,
	output wire i,
	input  wire o,
	input  wire oe,
	input  wire clk,
	input  wire rst
);

    wire raw_i;
	reg [2:0] state;

	if (BIDIR)
		SB_IO #(
			.PIN_TYPE    (6'b1101_00),   // Reg input, Reg+RegOE output
			.PULLUP      (1'b0),
			.IO_STANDARD ("SB_LVCMOS")
		) iob_I (
			.PACKAGE_PIN   (pad),
			.INPUT_CLK     (clk),
			.OUTPUT_CLK    (clk),
			.D_IN_0        (raw_i),
			.D_OUT_0       (o),
			.OUTPUT_ENABLE (oe),
		);
	else
		SB_IO #(
			.PIN_TYPE    (6'b0000_00),   // Reg input, No output
			.PULLUP      (1'b0),
			.IO_STANDARD ("SB_LVCMOS")
		) iob_I (
			.PACKAGE_PIN (pad),
			.INPUT_CLK   (clk),
			.D_IN_0      (raw_i)
		);

	always @(posedge clk or posedge rst)
		if (rst)
			state <= 3'b000;
		else
			casez ({raw_i, state})
				// Stay at 0
				4'b00??: state <= 3'b000;

				// Stay at 1
				4'b11??: state <= 3'b111;

				// Transition 0 -> 1
				4'b1000: state <= 3'b001;
				4'b1001: state <= 3'b010;
				4'b1010: state <= 3'b011;
				4'b1011: state <= 3'b111;

				// Transition 0 -> 1
				4'b0111: state <= 3'b110;
				4'b0110: state <= 3'b101;
				4'b0101: state <= 3'b100;
				4'b0100: state <= 3'b000;

				// Catch all
				default: state <= 3'b000;
			endcase

	assign i = state[2];

endmodule // sid_bus_if_debounce
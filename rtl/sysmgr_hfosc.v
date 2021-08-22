/*
 * sysmgr_hfosc.v
 *
 * vim: ts=4 sw=4
 *
 * CRG generating 48 MHz from internal SB_HFOSC
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module sysmgr_hfosc (
	input  wire rst_in,
	output wire clk_out,
	output wire rst_out
);

	// Signals
	wire clk_i;
	reg rst_i;
	reg [7:0] rst_cnt = 8'h00;

	// 48 MHz source
	SB_HFOSC #(
		.CLKHF_DIV("0b00")
	) osc_I (
		.CLKHFPU(1'b1),
		.CLKHFEN(1'b1),
		.CLKHF(clk_i)
	);

	assign clk_out = clk_i;

	// Logic reset generation
	// (need a larger delay here because without pll lock delay, BRAMs aren't
	//  ready in time ...)
	always @(posedge clk_i or posedge rst_in)
		if (rst_in)
			rst_cnt <= 8'h00;
		else if (rst_i)
			rst_cnt <= rst_cnt + 1;

	always @(posedge clk_i)
		rst_i <= ~&rst_cnt[7:4];

	assign rst_out = rst_i;

endmodule // sysmgr_hfosc

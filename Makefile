# The following license is from the icestorm project and specifically applies to this file only:
#
#  Permission to use, copy, modify, and/or distribute this software for any
#  purpose with or without fee is hereby granted, provided that the above
#  copyright notice and this permission notice appear in all copies.
#
#  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
#  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
#  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
#  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
#  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

PROJ = i2s_test
SRC_DIR = rtl
BUILD_DIR = build
SIM_DIR = sim
TOPFILE = $(addprefix $(SRC_DIR)/,top.v)
SRCS = i2c_state_machine.v i2c_master.v muacm.v sysmgr_hfosc.v sid.v env.v voice.v i2s.v spi.v
ALL_SRCS = $(addprefix $(SRC_DIR)/,$(SRCS))
DRAW_DIR = drawings
SEED = 1337
BOARD = redip-sid
DEVICE = up5k
PACKAGE = sg48
FREQ = 24 # MHz

ICE40_LIBS ?= $(shell yosys-config --datdir/ice40/cells_sim.v)

all: $(BUILD_DIR)/$(PROJ).bin $(BUILD_DIR)/$(PROJ).rpt

draw: $(addprefix $(DRAW_DIR)/, $(subst .v,.svg,$(TOPFILE))) $(addprefix $(DRAW_DIR)/,$(subst .v,.svg,$(SRCS))) clean_dot

clean_dot: 
	rm -f $(DRAW_DIR)/*.dot

$(DRAW_DIR)/%.svg: $(SRC_DIR)/%.v $(TOPFILE) $(ALL_SRCS)
	@mkdir -p $(@D)
	yosys -p 'read_verilog $<; show -prefix $(addprefix $(DRAW_DIR)/,$*) -format svg $*'

$(BUILD_DIR)/$(PROJ).json: $(TOPFILE) $(ALL_SRCS)
	@mkdir -p $(@D)
	yosys -f verilog -l $(BUILD_DIR)/$(PROJ).yslog -p 'read_verilog $^; synth_ice40 -json $@ -top top'

$(BUILD_DIR)/$(PROJ).asc: $(BUILD_DIR)/$(PROJ).json $(BOARD).pcf
	@mkdir -p $(@D)
	nextpnr-ice40 -l $(BUILD_DIR)/$(PROJ).nplog  --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $@ --pcf $(BOARD).pcf --seed $(SEED) --timing-allow-fail --json $<

$(BUILD_DIR)/$(PROJ).bin: $(BUILD_DIR)/$(PROJ).asc
	@mkdir -p $(@D)
	icepack $< $@

$(BUILD_DIR)/$(PROJ).rpt: $(BUILD_DIR)/$(PROJ).asc
	@mkdir -p $(@D)

$(BUILD_DIR)/i2c_state_machine_tb: $(SIM_DIR)/i2c_state_machine_tb.v $(ICE40_LIBS) $(ALL_SRCS)
	@mkdir -p $(@D)
	iverilog -g2012 -Wall -Wno-portbind -Wno-timescale -DSIM=1 -DNO_ICE40_DEFAULT_ASSIGNMENTS -o $@  $^

$(BUILD_DIR)/i2s_master_tb: $(SIM_DIR)/i2s_master_tb.v $(SRC_DIR)/i2s_master.v
	@mkdir -p $(@D)
	iverilog -g2012 -Wall -Wno-portbind -DSIM=1 -DNO_ICE40_DEFAULT_ASSIGNMENTS -o $@  $^

$(BUILD_DIR)/top_tb: $(SIM_DIR)/top_tb.v $(ICE40_LIBS) $(ALL_SRCS) $(TOPFILE)
	@mkdir -p $(@D)
	iverilog -g2012 -Wall -Wno-portbind -Wno-timescale -DSIM=1 -DNO_ICE40_DEFAULT_ASSIGNMENTS -o $@  $^

sim: $(BUILD_DIR)/i2c_state_machine_tb $(BUILD_DIR)/i2s_master_tb $(BUILD_DIR)/top_tb

prog: $(BUILD_DIR)/$(PROJ).bin
	dfu-util --device 1d50:6159:1d50:6156 --alt 0 -R --download $<

sudo-prog: $(BUILD_DIR)/$(PROJ).bin
	@echo 'Executing prog as root!!!'
	sudo dfu-util --device 1d50:6159:1d50:6156 --alt 0 -R --download $<

clean:
	rm -rf $(BUILD_DIR) obj_dir $(DRAW_DIR)

.SECONDARY:
.PHONY: all prog clean draw sudo-prog sim

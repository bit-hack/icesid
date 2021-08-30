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

PROJ = icesid
BUILD_DIR = build
SRCS = i2s.v spi.v top.v
ICESID_SRCS = sid.v env.v voice.v filter.v clip.v pot.v cic.v
ALL_SRCS = $(addprefix icesugar/,$(SRCS)) $(addprefix icesid/,$(ICESID_SRCS))
SEED = 1337
PCFFILE = icesugar/icesugar
DEVICE = up5k
PACKAGE = sg48
FREQ = 12 # MHz

all: $(BUILD_DIR)/$(PROJ).bin

$(BUILD_DIR)/$(PROJ).json: $(ALL_SRCS)
	@mkdir -p $(@D)
	yosys -f verilog -l $(BUILD_DIR)/$(PROJ).yslog -p 'read_verilog $^; synth_ice40 -json $@ -top top'

$(BUILD_DIR)/$(PROJ).asc: $(BUILD_DIR)/$(PROJ).json $(PCFFILE).pcf
	@mkdir -p $(@D)
	nextpnr-ice40 -l $(BUILD_DIR)/$(PROJ).nplog --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $@ --pcf $(PCFFILE).pcf --seed $(SEED) --json $<

$(BUILD_DIR)/$(PROJ).bin: $(BUILD_DIR)/$(PROJ).asc
	@mkdir -p $(@D)
	icepack $< $@

upload: $(BUILD_DIR)/$(PROJ).bin
	mv $(BUILD_DIR)/$(PROJ).bin /media/pi/iCELink

clean:
	rm -rf $(BUILD_DIR) obj_dir

.SECONDARY:
.PHONY: all prog clean

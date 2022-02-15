
ICESID_SRCS     = sid.v env.v voice.v filter.v clip.v pot.v mult.v output.v
ALL_ICESID_SRCS = $(addprefix icesid/,$(ICESID_SRCS))
BOARD           = reDIP-SID

ifeq ($(BOARD),reDIP-SID)
	include reDIP-SID/Makefile.mk
else
	include icesugar/Makefile.mk
endif

verilator:
	verilator --cc --exe --build    \
	-Wno-WIDTH                      \
	$(ALL_ICESID_SRCS)              \
	verilator/verilator.cpp         \
	--top-module sid                \
	-o icesidsim

clean:
	rm -rf $(BUILD_DIR) obj_dir

.SECONDARY:
.PHONY: all clean verilator

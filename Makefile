name = sid
pcf = icesugarnano.pcf
top = top
files = sid.v top.v

# pack asc format into bitstream
$(name).bin : $(name).asc
	icepack $(name).asc $(name).bin

# PNR step convert json into ice40 asc format
# $(name).asc : $(name).json
# 	nextpnr-ice40 \
# 	  --top $(top) \
# 	  --up5k \
# 	  --package sg48 \
# 	  --json $(name).json \
# 	  --pcf $(pcf) \
# 	  --asc $(name).asc \
# 	  --freq 48

# PNR step convert json into ice40 asc format
$(name).asc : $(name).json
	nextpnr-ice40 \
	  --top $(top) \
	  --lp1k \
	  --package cm36 \
	  --json $(name).json \
	  --pcf $(pcf) \
	  --asc $(name).asc \
	  --freq 12

# convert verilog into RTL json format
$(name).blif $(name).json : $(files)
	yosys \
	  -p "synth_ice40 -json $(name).json" \
	  $(files) \
	  -q \
	  -DICESUGARNANO

# cleanup files
clean:
	rm -rf *.blif *.asc *.bin *.json

.PHONY:	sim build upload
BIT	?= impl/pnr/usbcore.fs

upload:
	openFPGALoader --board tangprimer20k --write-sram $(BIT)

DIR	:= ../../rtl
OPT	:= -g2005-sv -D__icarus -Wall -I$(DIR)/ -I../../bench/

LIB	:= $(wildcard $(DIR)/*.v $(DIR)/arch/*.v $(DIR)/misc/*.v $(DIR)/fifo/*.v $(DIR)/uart/*.v)
SIM	:= $(wildcard ../../bench/arch/*.v) $(wildcard ../../bench/*.v)
SRC	:= $(wildcard *.v)
RTL	:= $(filter-out %_tb.v, $(SRC)) $(filter-out %_tb.v, $(LIB)) $(filter-out %_tb.v, $(SIM))
TB	:= $(filter %_tb.v, $(SRC))
OUT	:= $(TB:%.v=%.out)
VCD	:= $(OUT:%.out=%.vcd)

sim:	build $(VCD)

build:	$(OUT) $(RTL)

%.out:	%.v $(RTL)
	iverilog $(OPT) -o $@ -s $(*F) $^

%.vcd:	%.out
	./$<

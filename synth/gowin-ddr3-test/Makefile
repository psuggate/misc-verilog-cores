.PHONY:	sim build upload
BIT	?= impl/pnr/ddr3_test.fs

upload:
	openFPGALoader --board tangprimer20k --write-sram $(BIT)

DIR	:= ../../rtl

# Source paths for various Verilog cores
ARCH	:= $(DIR)/arch
AXIS	:= $(DIR)/axis
DDR3	:= $(DIR)/ddr3
FIFO	:= $(DIR)/fifo
MISC	:= $(DIR)/misc
UART	:= $(DIR)/uart

# Verilog dependencies
DEP	:= $(wildcard $(ARCH)/*.v $(AXIS)/*.v $(DDR3)/*.v $(FIFO)/*.v $(MISC)/*.v $(UART)/*.v)
CORES	:= $(filter-out %_tb.v, $(DEP))

LIB	:= $(filter-out %_tb.v, $(wildcard $(DIR)/*.v)) $(CORES)
SIM	:= $(wildcard ../../bench/arch/*.v) $(wildcard ../../bench/*.v)
SRC	:= $(wildcard *.v)
RTL	:= $(filter-out %_tb.v, $(SRC)) $(filter-out %_tb.v, $(LIB)) $(filter-out %_tb.v, $(SIM))

# Top-level testbenches and outputs
TB	:= $(filter %_tb.v, $(SRC))
OUT	:= $(TB:%.v=%.out)
VCD	:= $(OUT:%.out=%.vcd)

# Icarus settings & options
OPT	:= -g2005-sv -D__icarus -Wall -I$(DIR)/ -I../../bench/ -I$(DIR)/ddr3/ -I$(DIR)/axis/

sim:	build $(VCD)

build:	$(OUT) $(RTL)

%.out:	%.v $(RTL)
	iverilog $(OPT) -o $@ -s $(*F) $^

%.vcd:	%.out
	./$<

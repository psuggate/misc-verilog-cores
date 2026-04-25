.PHONY:	sim build upload
BIT	?= impl/pnr/gowin-ddr3-test.fs

upload:
	openFPGALoader --board tangprimer20k --write-sram $(BIT)

DIR	:= ../../rtl

# Source paths for various Verilog cores
ARCH	:= $(DIR)/arch
AXIS	:= $(DIR)/axis
DDR3	:= $(DIR)/ddr3
FIFO	:= $(DIR)/fifo
MISC	:= $(DIR)/misc
USB2	:= $(DIR)/usb

# Simulation module
VPI	:= ../../vpi
MOD	:= $(VPI)/ulpisim.vpi
CSRC	:= $(wildcard $(VPI)/*.c $(VPI)/*.h)

# Verilog dependencies
DEP	:= $(wildcard $(ARCH)/*.v $(AXIS)/*.v $(DDR3)/*.v $(FIFO)/*.v $(MISC)/*.v $(USB2)/*.v $(USB2)/mmio/*.v)
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
OPT	:= -g2005-sv -D__icarus -Wall -I$(DIR)/ -I$(USB2) -I../../bench/ -I$(DIR)/ddr3/ -I$(DIR)/axis/ -L$(VPI) -mulpisim

%.vpi:	$(CSRC)
	make -C $(VPI) build

sim:	build $(MOD) $(VCD)

build:	$(OUT) $(RTL)

%.out:	%.v $(RTL)
	iverilog $(OPT) -o $@ -s $(*F) $^

%.vcd:	%.out $(MOD)
	time vvp -M../../vpi -mulpisim ./$<

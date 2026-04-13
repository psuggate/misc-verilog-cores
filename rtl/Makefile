.PHONY:	all sim build clean

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../bench

SRC	:= $(wildcard *.v)
INC	:= $(wildcard *.vh)
PHY	:= $(wildcard arch/*.v) $(wildcard ../bench/arch/*.v)
LIB	:= $(wildcard misc/*.v) $(wildcard fifo/*.v) $(PHY) ../bench/ddr3.v
RTL	:= $(filter-out %_tb.v, $(SRC))

BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../build/%.out)
VCD	:= $(OUT:%.out=%.vcd)

sim:	build
	make -C axis sim
	make -C fifo sim
	make -C misc sim
	make -C usb sim

all:	build

build:	$(OUT)
	make -C axis build
	make -C fifo build
	make -C misc build
	make -C usb build

../build/%.out: %.v $(RTL) $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^

%.vcd: %.out
	cd $(<D) && ./$(<F) && touch $(@F)

clean:
	@rm -f $(OUT)
	@make -C axis clean
	@make -C fifo clean
	@make -C misc clean
	@make -C usb clean

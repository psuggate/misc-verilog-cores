.PHONY:	all sim build clean
all:	build

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../../axis -I..

LIB	:= $(wildcard ../../arch/*.v ../../fifo/*.v ../../axis/*.v ../../misc/*.v)
DEP	:= $(filter-out %_tb.v, $(LIB))
SRC	:= $(wildcard *.v)
RTL	:= $(filter-out %_tb.v, $(SRC)) $(DEP)

BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../../../build/%.out)
VCD	:= $(OUT:%.out=%.vcd)

build:	$(OUT)

sim:	$(VCD)

../../../build/%.out: %.v $(RTL)
	$(IVC) $(OPT) -o $@ -s $(*F) $^

%.vcd: %.out
	cd $(<D) && ./$(<F) && touch $(@F)

clean:
	@rm -f $(OUT)

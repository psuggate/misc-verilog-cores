.PHONY:	all sim build clean
all:	build
sim:	build

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../../axis

LIB	:= $(wildcard ../../arch/*.v ../../fifo/*.v ../../axis/*.v ../../misc/*.v)
DEP	:= $(filter-out %_tb.v, $(LIB))

SRC	:= $(wildcard *.v)
RTL	:= $(filter-out %_tb.v, $(SRC)) $(DEP)

BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../../../build/%.out)

build:	$(OUT)

../../../build/%.out: %.v $(RTL)
	$(IVC) $(OPT) -o $@ -s $(*F) $^

clean:
	@rm -f $(OUT)

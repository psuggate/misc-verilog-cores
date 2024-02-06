.PHONY:	sim all clean
all:	sim

OUT	:= $(wildcard *_tb.out)
VCD	:= $(OUT:%.out=%.vcd)

sim:	$(VCD)

clean:
	rm -f *.vcd *.out

%.vcd:	%.out
	./$<

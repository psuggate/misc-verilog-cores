.PHONY:	sim all clean vpi
all:	vpi sim

OUT	:= $(wildcard *_tb.out)
VCD	:= $(OUT:%.out=%.vcd)

sim:	vpi $(VCD)

vpi:
	@make -C ../vpi all

clean:
	rm -f *.vcd *.out

%.vcd:	%.out
	vvp -M../vpi -mulpisim ./$<

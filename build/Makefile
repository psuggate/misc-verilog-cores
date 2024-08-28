.PHONY:	sim all clean vpi
all:	vpi sim

OUT	:= $(wildcard *_tb.out)
USB	:= $(wildcard *usb*.out)
VCD	:= $(OUT:%.out=%.vcd)
USBVCD	:= $(USB:%.out=%.vcd)

sim:	vpi $(VCD)

usbsim:	vpi $(USBVCD)

vpi:
	@make -C ../vpi all

clean:
	rm -f *.vcd *.out

%.vcd:	%.out
	vvp -M../vpi -mulpisim ./$<

.PHONY:	all build clean

INC	?= $(wildcard *.h) $(wildcard usb/*.h)
SRC	?= $(wildcard *.c)
DEP	?= $(wildcard usb/*.c)
OBJ	?= $(SRC:.c=.o) $(DEP:usb/%.c=%.o)
VPI	?= ulpisim.vpi


all:	build

build:	$(VPI) $(OBJ) $(INC)

clean:
	make -C usb clean
	rm -f $(OBJ) $(VPI) $(RUN)

%.o: %.c $(INC)
	gcc -c -fpic -O2 -I/usr/include/iverilog $<

%.o: usb/%.c $(INC)
	gcc -c -fpic -O2 -I/usr/include/iverilog $<

%.vpi:	$(OBJ)
	gcc -shared -o $@ $^ -lvpi

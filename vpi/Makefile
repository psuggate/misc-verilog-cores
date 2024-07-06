.PHONY:	all build clean

INC	?= $(wildcard *.h)
SRC	?= $(wildcard *.c)
OBJ	?= $(SRC:.c=.o)
VPI	?= ulpisim.vpi

all:	build

build:	$(VPI) $(OBJ) $(INC)

clean:
	@rm -f $(OBJ) $(VPI)

%.o: %.c
	gcc -c -fpic -O2 -I/usr/include/iverilog $<

%.vpi:	$(OBJ)
	gcc -shared -o $@ $^ -lvpi

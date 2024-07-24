.PHONY:	all build clean

INC	?= $(wildcard *.h)
SRC	?= $(wildcard *.c)
OBJ	?= $(SRC:.c=.o)
VPI	?= ulpisim.vpi
RUN	?= ulpisim


all:	build

build:	$(VPI) $(OBJ) $(INC)
	gcc -shared $(OBJ) -lm -lvpi -o $(RUN)

clean:
	@rm -f $(OBJ) $(VPI)

%.o: %.c
	gcc -c -fpic -O2 -I/usr/include/iverilog $<

%.vpi:	$(OBJ)
	gcc -shared -o $@ $^ -lvpi

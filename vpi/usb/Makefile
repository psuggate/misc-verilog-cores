.PHONY:	all build clean

INC	?= $(wildcard *.h)
SRC	?= $(wildcard *.c)
OBJ	?= $(SRC:.c=.o)
RUN	?= usbmodel


all:	build

build:	$(OBJ) $(INC)
	gcc $(OBJ) -lm -o $(RUN)

clean:
	rm -f $(OBJ) $(RUN)

%.o: %.c
	gcc -c -O2 $<

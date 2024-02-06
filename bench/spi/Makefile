.PHONY:	all dir build run clean

IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall

BUILD	:= ../../build
RTLDIR	:= ../../rtl
SPI	:= $(RTLDIR)/spi

LIB	:= wb_sram.v afifo16.v $(RTLDIR)/fifo/fifo_dc_gray.v $(RTLDIR)/fifo/afifo_gray.v
DEP	:= $(LIB) $(SPI)/spi_layer.v $(SPI)/spi_slave.v $(SPI)/spi_target.v $(SPI)/spi_master.v

TB	?= $(wildcard *_tb.v)
OUT	?= $(TB:%.v=$(BUILD)/%.out)

all:	dir $(OUT) run

# all:	$(DEP) spi_slave_tb.v
# 	@echo "TB: $(TB)"
# 	$(IVC) $(OPT) -o $(BUILD)/spi_tb.out $(DEP) spi_slave_tb.v

build:	$(OUT)

run:	all
	@$(BUILD)/spi_slave_tb.out

dir:
	@mkdir -p $(BUILD)

clean:
	rm -f $(OUT) *.vcd

../../build/%.out: %.v $(LIB) $(DEP)
	$(IVC) $(OPT) -o $@ -s $(*F) $^

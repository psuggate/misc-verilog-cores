.PHONY:	all dir run clean

IVC	= iverilog
OPT	= -D__icarus

OUT	= ../../build

RTL	= ../../rtl
SPI	= $(RTL)/spi
LIB	= wb_sram.v afifo16.v $(RTL)/fifo/fifo_dc_gray.v $(RTL)/fifo/afifo_gray.v
DEP	= $(LIB) $(SPI)/spi_layer.v $(SPI)/spi_slave.v $(SPI)/spi_target.v $(SPI)/spi_master.v

all: ${DEP} spi_slave_tb.v
	$(IVC) $(OPT) -o $(OUT)/spi_tb.out $(DEP) spi_slave_tb.v

run: all
	@$(OUT)/spi_tb.out

dir:
	@mkdir $(OUT)

clean:
	rm -f $(OUT)/spi_tb.out

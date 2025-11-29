PROJECT  := usbddr3
TOP      := usb_ddr3_top
FAMILY   := GW2A-18C
DEVICE   := GW2A-LV18PG256C8/I7
CST	 := gowin-ddr3-test.cst
SDC	 := gowin-ddr3-test.sdc
GW_SH	 := /opt/gowin/IDE/bin/gw_sh

VROOT 	 := $(dir $(abspath $(CURDIR)/..))
RTL	 = $(VROOT)/rtl
BENCH	 = $(VROOT)/bench

ARCH_V	:= \
        ${RTL}/arch/gw2a_ddr3_phy.v \
        ${RTL}/arch/gw2a_ddr_iob.v \
        ${RTL}/arch/gw2a_rpll.v
AXIS_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/axis/*.v))
DDR3_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/ddr3/*.v))
FIFO_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/fifo/*.v))
MISC_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/misc/*.v))
UART_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/uart/*.v))
USB2_V	:= $(filter-out %_tb.v, $(wildcard $(RTL)/usb/*.v))

SOURCES	:= \
	$(ARCH_V) $(AXIS_V) $(DDR3_V) $(FIFO_V) $(MISC_V) $(UART_V) $(USB2_V) \
	ddr3_top.v memreq.v $(TOP).v

gowin_build: impl/pnr/project.fs

$(PROJECT).tcl: $(SOURCES)
	@echo ${SOURCES}
	@echo "set_device -name $(FAMILY) $(DEVICE)" > $(PROJECT).tcl
	@for VAR in $^; do echo $$VAR | grep -s -q "\.v$$" && echo "add_file $$VAR" >> $(PROJECT).tcl; done
	@echo "add_file ${CST}" >> $(PROJECT).tcl
	@echo "add_file $(SDC)" >> $(PROJECT).tcl
	@echo "set_option -top_module $(TOP)" >> $(PROJECT).tcl
	@echo "set_option -verilog_std sysv2017" >> $(PROJECT).tcl
	@echo "set_option -vhdl_std vhd2008" >> $(PROJECT).tcl
	@echo "set_option -use_sspi_as_gpio 1" >> $(PROJECT).tcl
	@echo "set_option -use_mspi_as_gpio 1" >> $(PROJECT).tcl
	@echo "set_option -use_done_as_gpio 1" >> $(PROJECT).tcl
	@echo "set_option -use_ready_as_gpio 1" >> $(PROJECT).tcl
	@echo "set_option -use_reconfign_as_gpio 1" >> $(PROJECT).tcl
	@echo "set_option -use_i2c_as_gpio 1" >> $(PROJECT).tcl
	@echo "run all" >> $(PROJECT).tcl

impl/pnr/project.fs: $(PROJECT).tcl
	${GW_SH} $(PROJECT).tcl

gowin_load: impl/pnr/project.fs
	openFPGALoader --board tangprimer20k --write-sram impl/pnr/project.fs

clean:
	rm -f $(PROJECT).tcl

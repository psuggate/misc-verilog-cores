PROJECT  := usbcore
TOP      := usb_demo_top
FAMILY   := GW2A-18C
DEVICE   := GW2A-LV18PG256C8/I7
CST	 := gw2a-tang-primer.cst
GW_SH	 := /opt/gowin/IDE/bin/gw_sh

VROOT 	 :=  $(dir $(abspath $(CURDIR)/..))
RTL	 = $(VROOT)/rtl
BENCH	 = $(VROOT)/bench

VERILOGS := ${BENCH}/spi/spi_to_spi.v \
        ${RTL}/arch/gw2a_ddr3_phy.v \
        ${RTL}/arch/gw2a_ddr_iob.v \
        ${RTL}/arch/gw2a_rpll.v \
        ${RTL}/axis/axi_chunks.v \
        ${RTL}/axis/axis_adapter.v \
        ${RTL}/axis/axis_chop.v \
        ${RTL}/axis/axis_clean.v \
        ${RTL}/axis/axis_fifo.v \
        ${RTL}/axis/axis_demux.v \
        ${RTL}/axis/axis_mux.v \
        ${RTL}/axis/axis_skid.v \
        ${RTL}/axis/skid_loader.v \
        ${RTL}/ddr3/axi_ddr3_lite.v \
        ${RTL}/ddr3/axi_rd_path.v \
        ${RTL}/ddr3/axi_wr_path.v \
        ${RTL}/ddr3/ddr3_axi_ctrl.v \
        ${RTL}/ddr3/ddr3_bypass.v \
        ${RTL}/ddr3/ddr3_cfg.v \
        ${RTL}/ddr3/ddr3_ddl.v \
        ${RTL}/ddr3/ddr3_fsm.v \
        ${RTL}/fifo/afifo_gray.v \
        ${RTL}/fifo/axis_afifo.v \
        ${RTL}/fifo/packet_fifo.v \
        ${RTL}/fifo/sync_fifo.v \
        ${RTL}/misc/hex_dump.v \
        ${RTL}/misc/shift_register.v \
        ${RTL}/spi/axis_spi_master.v \
        ${RTL}/spi/axis_spi_target.v \
        ${RTL}/spi/spi_layer.v \
        ${RTL}/spi/spi_master.v \
        ${RTL}/spi/spi_target.v \
        ${RTL}/uart/uart.v \
        ${RTL}/uart/uart_rx.v \
        ${RTL}/uart/uart_tx.v \
        ${RTL}/usb/ctl_pipe0.v \
        ${RTL}/usb/ep_bulk_in.v \
        ${RTL}/usb/ep_bulk_out.v \
        ${RTL}/usb/line_state.v \
        ${RTL}/usb/protocol.v \
        ${RTL}/usb/stdreq.v \
        ${RTL}/usb/ulpi_decoder.v \
        ${RTL}/usb/ulpi_encoder.v \
        ${RTL}/usb/ulpi_reset.v \
        ${RTL}/usb/usb_ulpi_core.v \
        ${RTL}/usb/usb_ulpi_top.v \
        usb_demo_top.v

gowin_build: impl/pnr/project.fs

$(PROJECT).tcl: $(VERILOGS)
	@echo ${VERILOGS}
	@echo "set_device -name $(FAMILY) $(DEVICE)" > $(PROJECT).tcl
	@for VAR in $?; do echo $$VAR | grep -s -q "\.v$$" && echo "add_file $$VAR" >> $(PROJECT).tcl; done
	@echo "add_file ${CST}" >> $(PROJECT).tcl
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
	openFPGALoader -b tangprimer20k impl/pnr/project.fs -f

clean:
	rm -f $(PROJECT).tcl

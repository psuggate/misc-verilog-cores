`timescale 1ns / 100ps
module ddr3_cfg_tb;

  // -- Simulation Settings -- //

  // DDR3 SRAM Timings
  localparam DDR_FREQ_MHZ = 100;

  `include "ddr3_settings.vh"

  // Trims an additional clock-cycle of latency, if '1'
  parameter LOW_LATENCY = 1'b0;  // 0 or 1

  localparam DDR_ROW_BITS = 13;
  localparam RSB = DDR_ROW_BITS - 1;

  parameter DDR_COL_BITS = 10;
  localparam CSB = DDR_COL_BITS - 1;

  // Data-path and address settings
  localparam WIDTH = 32;
  localparam MSB = WIDTH - 1;

  localparam MASKS = WIDTH / 8;
  localparam SSB = MASKS - 1;

  localparam ADDRS = DDR_COL_BITS + DDR_ROW_BITS + 3 - 1;
  localparam ASB = ADDRS - 1;

  localparam REQID = 4;
  localparam ISB = REQID - 1;

  // -- Simulation Data -- //

  initial begin
    $dumpfile("ddr3_cfg_tb.vcd");
    #60000 $dumpvars(0, ddr3_cfg_tb);
    #20000 $finish;  // todo ...
  end

  // -- Globals -- //

  reg osc = 1'b1;
  reg ddr = 1'b1;
  reg rst = 1'b0;

  always #5.0 osc <= ~osc;
  always #2.5 ddr <= ~ddr;

  initial begin
    rst <= 1'b1;
    #200 rst <= 1'b0;
  end

  wire locked, clock, reset;
  wire clk_ddr, clk_ddr_dqs, clk_ref;

  assign #50 locked = 1'b1;
  assign clk_ddr = ddr;
  assign clock = osc;
  assign reset = rst | ~locked;

  // -- DDR3 Configurator for a Memory Controller -- //

  wire ddl_run, ddl_req, ddl_seq, ddl_rdy, ddl_ref;
  wire [2:0] ddl_cmd, ddl_ba;
  wire [RSB:0] ddl_adr;

  // Memory Controller Signals (to the DDL/PHY)
  wire ctl_req, ctl_seq, ctl_run, ctl_rdy, ctl_ref;
  wire [2:0] ctl_cmd, ctl_ba;
  wire [RSB:0] ctl_adr;

  // SDRAM Configuration Signals
  wire cfg_req, cfg_run, cfg_rdy, cfg_ref;
  wire [2:0] cfg_cmd, cfg_ba;
  wire [RSB:0] cfg_adr;

  // Requests/responses to/from the Memory Controller
  reg fsm_wrreq, fsm_wrlst, fsm_rdreq, fsm_rdlst;
  wire fsm_rdack, fsm_rderr, fsm_wrack, fsm_wrerr;
  reg [ISB:0] fsm_wrtid, fsm_rdtid;
  reg [ASB:0] fsm_wradr, fsm_rdadr;

  // AXI <-> {FSM, DDL} signals
  wire wr_ready, rd_valid, rd_last;
  wire [MSB:0] rd_data;
  reg wr_valid, wr_last, rd_ready;
  reg [SSB:0] wr_mask;
  reg [MSB:0] wr_data;

  // DFI <-> PHY
  wire dfi_rst_n, dfi_cke, dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
  wire dfi_odt, dfi_wstb, dfi_wren, dfi_rden, dfi_valid, dfi_last;
  wire [  2:0] dfi_bank;
  wire [RSB:0] dfi_addr;
  wire [SSB:0] dfi_mask;
  wire [MSB:0] dfi_wdata, dfi_rdata;

  // PHY <-> DDR3
  wire ddr_ck_p, ddr_ck_n;
  wire ddr_rst_n, ddr_cke, ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  wire ddr_odt;
  wire [2:0] ddr_ba;
  wire [RSB:0] ddr_a;
  wire [1:0] ddr_dm, ddr_dqs_p, ddr_dqs_n;
  wire [15:0] ddr_dq;

  assign rd_ready = 1'b1;

  // -- Manage the REFRESH Requests -- //

  reg mem_req;
  reg [2:0] mem_cmd;

  assign ctl_cmd = cfg_run ? mem_cmd : cfg_cmd;
  assign ctl_req = cfg_run ? mem_req : cfg_req;
  assign ctl_ba  = cfg_run ? 'bx : cfg_ba;
  assign ctl_adr = cfg_run ? 'bx : cfg_adr;

  assign cfg_rdy = ddl_rdy;
  assign ctl_rdy = ddl_rdy;

  always @(posedge clock) begin
    if (reset || !cfg_run) begin
      mem_cmd <= CMD_NOOP;
      mem_req <= 1'b0;
    end else begin
      if (!mem_req && cfg_ref) begin
        mem_cmd <= CMD_REFR;
        mem_req <= 1'b1;
      end else if (mem_req && ctl_rdy) begin
        mem_req <= 1'b0;
        mem_cmd <= CMD_NOOP;
      end
    end
  end

  // -- Use the Memory Controller FSM to Generate Requests -- //

  reg [6:0] counter;
  reg fsm_run, mem_run, rfc;

  always @(posedge clock) begin
    if (reset) begin
      fsm_run <= 1'b0;
      mem_run <= 1'b0;
      rfc <= 1'b0;
      counter <= 7'd020;
      fsm_wrreq <= 1'b0;
      fsm_wrlst <= 1'b0;
      fsm_rdreq <= 1'b0;
      fsm_rdlst <= 1'b0;
    end else if (cfg_run && counter > 0) begin
      counter <= counter - 1;
      fsm_run <= counter == 7'd001;
    end else if (fsm_run && cfg_ref && ddl_rdy) begin
      rfc <= 1'b1;
      mem_run <= 1'b1;
    end
  end

  reg [127:0] data;

  initial begin
    while (!reset) begin
      @(posedge clock);
    end
    @(posedge clock);
    while (reset) begin
      @(posedge clock);
    end

    @(posedge clock);
    while (!cfg_run || !ddl_run || !fsm_run) begin
      @(posedge clock);
    end

    $display("%10t: STORE", $time);
    @(posedge clock);
    mem_store(16, 1, 1, 'bx);

    @(posedge clock);
    @(posedge clock);

    // 2x BL8 as part of a 32B burst
    $display("%10t: STORE", $time);
    @(posedge clock);
    mem_store(0, 0, 2, 'bx);
    mem_store(8, 1, 2, 'bx);

    @(posedge clock);
    @(posedge clock);

    $display("%10t: FETCH", $time);
    @(posedge clock);
    mem_fetch(8, 0, 5, data);
    mem_fetch(16, 1, 5, data);

    @(posedge clock);
    @(posedge clock);

    $display("%10t: FETCH", $time);
    @(posedge clock);
    mem_fetch(8, 0, 3, data);
    mem_fetch(16, 1, 3, data);

    @(posedge clock);
    @(posedge clock);
  end

  // -- Fake Write Data -- //

  reg  [1:0] wr_count;
  wire [1:0] wr_cnext = wr_count + 1;

  always @(posedge clock) begin
    if (reset) begin
      wr_valid <= 1'b0;
      wr_count <= 2'h0;
    end else if (fsm_run) begin
      if (!wr_valid) begin
        wr_valid <= 1'b1;
        wr_data  <= $urandom;
        wr_mask  <= {MASKS{1'b1}};
      end else if (wr_ready) begin
        wr_last  <= wr_count == 2'h2;
        wr_mask  <= {MASKS{1'b1}};
        wr_data  <= $urandom;
        wr_count <= wr_cnext;
      end
    end
  end

  // -- DDR3 Simulation Model from Micron -- //

  ddr3 ddr3_sdram_inst (
      .rst_n(ddr_rst_n),
      .ck(ddr_ck_p),
      .ck_n(ddr_ck_n),
      .cke(ddr_cke),
      .cs_n(ddr_cs_n),
      .ras_n(ddr_ras_n),
      .cas_n(ddr_cas_n),
      .we_n(ddr_we_n),
      .dm_tdqs(ddr_dm),
      .ba(ddr_ba),
      .addr({1'b0, ddr_a}),
      .dq(ddr_dq),
      .dqs(ddr_dqs_p),
      .dqs_n(ddr_dqs_n),
      .tdqs_n(),
      .odt(ddr_odt)
  );

  // -- DDR3 PHI Interface Modules -- //

  generic_ddr3_phy #(
      .DDR3_WIDTH(16),  // (default)
      .ADDR_BITS(DDR_ROW_BITS)  // default: 14
  ) ddr3_phy_inst (
      .clock  (clock),
      .reset  (reset),
      .clk_ddr(clk_ddr),

      .dfi_rst_ni(dfi_rst_n),
      .dfi_cke_i (dfi_cke),
      .dfi_cs_ni (dfi_cs_n),
      .dfi_ras_ni(dfi_ras_n),
      .dfi_cas_ni(dfi_cas_n),
      .dfi_we_ni (dfi_we_n),
      .dfi_odt_i (dfi_odt),
      .dfi_bank_i(dfi_bank),
      .dfi_addr_i(dfi_addr),

      .dfi_wstb_i(dfi_wstb),
      .dfi_wren_i(dfi_wren),
      .dfi_mask_i(dfi_mask),
      .dfi_data_i(dfi_wdata),

      .dfi_rden_i(dfi_rden),
      .dfi_rvld_o(dfi_valid),
      .dfi_last_o(dfi_last),
      .dfi_data_o(dfi_rdata),

      .ddr3_ck_po(ddr_ck_p),
      .ddr3_ck_no(ddr_ck_n),
      .ddr3_cke_o(ddr_cke),
      .ddr3_rst_no(ddr_rst_n),
      .ddr3_cs_no(ddr_cs_n),
      .ddr3_ras_no(ddr_ras_n),
      .ddr3_cas_no(ddr_cas_n),
      .ddr3_we_no(ddr_we_n),
      .ddr3_odt_o(ddr_odt),
      .ddr3_ba_o(ddr_ba),
      .ddr3_a_o(ddr_a),
      .ddr3_dm_o(ddr_dm),
      .ddr3_dqs_pio(ddr_dqs_p),
      .ddr3_dqs_nio(ddr_dqs_n),
      .ddr3_dq_io(ddr_dq)
  );

  // Inserts NOP's between memory-controller commands to satisfy DDR3 timing
  // parameters.
  ddr3_ddl #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .LOW_LATENCY (LOW_LATENCY),
      .DFI_DQ_WIDTH(WIDTH)
  ) ddr3_ddl_inst (
      .clock(clock),
      .reset(reset),

      .ddr_cke_i(dfi_cke),
      .ddr_cs_ni(dfi_cs_n),

      .ctl_run_o(ddl_run),
      .ctl_req_i(ddl_req),
      .ctl_seq_i(ddl_seq),
      .ctl_rdy_o(ddl_rdy),
      .ctl_cmd_i(ddl_cmd),
      .ctl_ba_i (ddl_ba),
      .ctl_adr_i(ddl_adr),

      .mem_wvalid_i(wr_valid),
      .mem_wready_o(wr_ready),
      .mem_wlast_i (wr_last),
      .mem_wrmask_i(wr_mask),
      .mem_wrdata_i(wr_data),

      .mem_rvalid_o(rd_valid),
      .mem_rready_i(rd_ready),
      .mem_rlast_o (rd_last),
      .mem_rddata_o(rd_data),

      .dfi_ras_no(dfi_ras_n),
      .dfi_cas_no(dfi_cas_n),
      .dfi_we_no (dfi_we_n),
      .dfi_bank_o(dfi_bank),
      .dfi_addr_o(dfi_addr),
      .dfi_wstb_o(dfi_wstb),
      .dfi_wren_o(dfi_wren),
      .dfi_mask_o(dfi_mask),
      .dfi_data_o(dfi_wdata),
      .dfi_rden_o(dfi_rden),
      .dfi_rvld_i(dfi_valid),
      .dfi_last_i(dfi_last),
      .dfi_data_i(dfi_rdata)
  );

  ddr3_fsm #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .REQID(REQID),
      .ADDRS(ADDRS)
  ) ddr3_fsm_inst (
      .clock(clock),
      .reset(~fsm_run),

      .mem_wrreq_i(fsm_wrreq),  // Bus -> Controller requests
      .mem_wrlst_i(fsm_wrlst),
      .mem_wrack_o(fsm_wrack),
      .mem_wrerr_o(fsm_wrerr),
      .mem_wrtid_i(fsm_wrtid),
      .mem_wradr_i(fsm_wradr),

      .mem_rdreq_i(fsm_rdreq),
      .mem_rdlst_i(fsm_rdlst),
      .mem_rdack_o(fsm_rdack),
      .mem_rderr_o(fsm_rderr),
      .mem_rdtid_i(fsm_rdtid),
      .mem_rdadr_i(fsm_rdadr),

      .cfg_req_i(cfg_req),  // Configuration port
      .cfg_rdy_o(cfg_rdy),
      .cfg_cmd_i(cfg_cmd),
      .cfg_ba_i (cfg_ba),
      .cfg_adr_i(cfg_adr),

      .ddl_req_o(ddl_req),  // Controller <-> DFI
      .ddl_seq_o(ddl_seq),
      .ddl_rdy_i(ddl_rdy),
      .ddl_ref_i(cfg_ref),  // todo ...
      .ddl_cmd_o(ddl_cmd),
      .ddl_ba_o (ddl_ba),
      .ddl_adr_o(ddl_adr)
  );

  // -- Module Under Test -- //

  wire cfg_valid;
  wire [31:0] cfg_data;

  assign cfg_valid = 1'b0;
  assign cfg_data  = 'bx;

  ddr3_cfg #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS)
  ) ddr3_cfg_inst (
      .clock(clock),
      .reset(reset),

      .dfi_rst_no(dfi_rst_n),  // Control these IOB's directly
      .dfi_cke_o (dfi_cke),
      .dfi_cs_no (dfi_cs_n),
      .dfi_odt_o (dfi_odt),

      .ctl_req_o(cfg_req),  // Memory controller signals
      .ctl_run_o(cfg_run),  // When initialisation has completed
      .ctl_rdy_i(cfg_rdy),
      .ctl_cmd_o(cfg_cmd),
      .ctl_ref_o(cfg_ref),
      .ctl_ba_o (cfg_ba),
      .ctl_adr_o(cfg_adr)
  );

  // -- Perform write transfer (128-bit) -- //

  task mem_store;
    input [ASB:0] addr;
    input last;
    input [ISB:0] tid;
    input [127:0] data;
    begin
      fsm_wrreq <= 1'b1;
      fsm_wrlst <= last;
      fsm_wrtid <= tid;
      fsm_wradr <= addr;

      while (!fsm_wrack) begin
        @(posedge clock);
      end

      fsm_wrreq <= 1'b0;
      @(posedge clock);

      // todo: tx data stuffs
    end
  endtask  // mem_store

  // -- Perform read transfer (128-bit) -- //

  task mem_fetch;
    input [ASB:0] addr;
    input last;
    input [ISB:0] tid;
    output [127:0] data;
    begin
      fsm_rdreq <= 1'b1;
      fsm_rdlst <= last;
      fsm_rdtid <= tid;
      fsm_rdadr <= addr;

      @(posedge clock);

      while (!fsm_rdack) begin
        @(posedge clock);
      end

      fsm_rdreq <= 1'b0;
      @(posedge clock);

      // todo: rx data stuffs
    end
  endtask  // mem_fetch


endmodule  /* ddr3_cfg_tb */

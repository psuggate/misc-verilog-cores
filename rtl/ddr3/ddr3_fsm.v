`timescale 1ns / 100ps
/**
 * Issues DDR3 commands based on the read-request and write-request FIFO inputs.
 *
 * Specifics of DDR3 initialisation and timings are handled one level down, by
 * the "DFI" module. This module schedules row-activations, bank-precharging,
 * read-requests, and data-writes.
 */
module ddr3_fsm #(
  // Sets DDR3 SRAM Timings
  parameter DDR_FREQ_MHZ = 100,

  // If enabled, the {wrlst, rdlst} are used to decide when to ACTIVATE and
  // PRECHARGE rows
  // todo:
  parameter WRLAST_ENABLE = 1'b1,
  parameter RDLAST_ENABLE = 1'b1,

  // Request ID's are represent the order that commands are accepted at the bus/
  // transaction layer, and if used, the memory controller will respect this
  // ordering, when reads and writes access overlapping areas of memory.
  parameter REQID = 4,
  localparam ISB = REQID - 1,

  // Defaults for 1Gb, 16x SDRAM
  parameter DDR_ROW_BITS = 13,
  localparam RSB = DDR_ROW_BITS - 1,
  parameter DDR_COL_BITS = 10,
  localparam CSB = DDR_COL_BITS - 1,

  // Default is '{row, bank, col} <= addr_i;' -- this affects how often banks will
  // need PRECHARGE commands. Enabling this alternate {bank, row, col} ordering
  // may help for some workloads; e.g., when all but the upper (burst) addresses
  // are not correlated in time?
  // todo: ...
  parameter BANK_ROW_COL = 0,

  // Note: all addresses for requests must be word- and burst- aligned. Therefore,
  //   for a x16 DDR3 device, each transfer is 16 bytes, so the lower 4-bits are
  //   not passed to this controller.
  // Note: a 1Gb, x16, DDR3 SDRAM has:
  //    - 13b row address bits;
  //    -  3b bank address bits;
  //    - 10b column address bits; and
  //    - 2kB page-size,
  //   and the lower 3b of the column address are ignored by this module. So a 23b
  //   address is required.
  // Todo: in order to support wrapping-bursts; e.g., for a CPU cache, will need
  //   the lower 3b ??
  parameter ADDRS = 23,
  localparam ASB = ADDRS - 1
) (
  input arst_n,  // Global, asynchronous reset

  input clock,  // Shared clock domain for the memory-controller
  input reset,  // Synchronous reset

  // Write-request port
  input mem_wrreq_i,
  input mem_wrlst_i,  // If asserted, then LAST of burst
  output mem_wrack_o,
  output mem_wrerr_o,
  input [ISB:0] mem_wrtid_i,
  input [ASB:0] mem_wradr_i,

  // Read-request port
  input mem_rdreq_i,
  input mem_rdlst_i,  // If asserted, then LAST of burst
  output mem_rdack_o,
  output mem_rderr_o,
  input [ISB:0] mem_rdtid_i,
  input [ASB:0] mem_rdadr_i,

  // Configuration port
  input cfg_req_i,
  output cfg_rdy_o,
  input [2:0] cfg_cmd_i,
  input [2:0] cfg_ba_i,
  input [RSB:0] cfg_adr_i,

  // DDR Data-Layer control signals
  // Note: all state-transitions are gated by the 'ddl_rdy_i' signal
  output ddl_req_o,
  output ddl_seq_o,
  input ddl_rdy_i,
  input ddl_ref_i,
  output [2:0] ddl_cmd_o,
  output [2:0] ddl_ba_o,
  output [RSB:0] ddl_adr_o
);

  //
  // Todo:
  //  - detect same bank+row, for subsequent commands
  //     + long-bursts that cross page boundaries ?
  //     + "coalesce" reads and/or writes to same pages ?
  //  - auto-precharge when required
  //  - command ordering (using transaction ID's)
  //  - scheduling for read- & write- ports:
  //     + command interleaving to hide ACTIVATE & PRECHARGE delays ?
  //     + "fairness"
  //  - track the active row for each bank
  //  - command-queuing ? I.e., given the read- and write- ports, can commands be
  //    determined, and pushed to a FIFO well-ahead of their actual dispatch ?
  //  - refresh issuing, as this can be flexible ?
  //  - which part of the address should map to the bank bits?
  //

  // -- Constants -- //

`include "ddr3_settings.vh"

  // DDR3 controller states
  localparam [4:0] ST_IDLE = 5'b10000;
  localparam [4:0] ST_READ = 5'b01000;
  localparam [4:0] ST_WRIT = 5'b00100;
  localparam [4:0] ST_ACTV = 5'b00010;
  localparam [4:0] ST_REFR = 5'b00001;

  // Precharge bits
  // Todo: does not handle the x4 SDRAMs
  localparam PBITS = DDR_ROW_BITS - DDR_COL_BITS;
  localparam PZERO = {PBITS{1'b0}};
  localparam PUNIT = {{PSB{1'b0}}, 1'b1};
  localparam PSB = PBITS - 1;

  // -- FSM Settings, Signals, and Registers -- //

  reg [4:0] snext, state;
  reg [RSB:0] adr_c, adr_q, row_c, row_q;
  reg [CSB:0] col_c, col_q;
  reg [2:0] ba_c, ba_q, cmd_c, cmd_q;
  reg [PSB:0] pre_c, pre_q;
  reg wak_c, wrack, rak_c, rdack, req_c, req_q, wen_c, wen_q;

  assign cfg_rdy_o = ddl_rdy_i;

  assign mem_wrack_o = wrack;
  assign mem_wrerr_o = 1'b0;
  assign mem_rdack_o = rdack;
  assign mem_rderr_o = 1'b0;

  assign ddl_req_o = req_q;
  assign ddl_seq_o = pre_q == 0;
  assign ddl_cmd_o = cmd_q;
  assign ddl_ba_o = ba_q;
  assign ddl_adr_o = adr_q;

  // -- FSM Logics -- //

  always @* begin
    adr_c = adr_q;
    col_c = col_q;
    ba_c  = ba_q;
    pre_c = pre_q;
    wak_c = 1'b0;
    rak_c = 1'b0;
    cmd_c = cmd_q;
    req_c = req_q;
    wen_c = wen_q;
    snext = state;

    case (state)
      ST_IDLE: begin
        wen_c = 1'b0;
        if (ddl_ref_i) begin
          req_c = 1'b1;
          pre_c = PUNIT;
          adr_c = {pre_c, col_c};
          cmd_c = CMD_REFR;
          snext = ST_REFR;
        end else if (mem_rdreq_i) begin
          {adr_c, ba_c, col_c} = mem_rdadr_i;
          req_c = 1'b1;
          pre_c = mem_rdlst_i ? PUNIT : PZERO;
          rak_c = 1'b1;
          wen_c = 1'b0;
          cmd_c = CMD_ACTV;
          snext = ST_ACTV;
        end else if (mem_wrreq_i) begin
          {adr_c, ba_c, col_c} = mem_wradr_i;
          req_c = 1'b1;
          pre_c = mem_wrlst_i ? PUNIT : PZERO;
          wak_c = 1'b1;
          wen_c = 1'b1;
          cmd_c = CMD_ACTV;
          snext = ST_ACTV;
        end
      end

      ST_ACTV: begin
        if (ddl_rdy_i) begin
          adr_c = {pre_q, col_q};
          cmd_c = wen_q ? CMD_WRIT : CMD_READ;
          snext = wen_q ? ST_WRIT : ST_READ;
        end
      end

      ST_WRIT: begin
        if (ddl_rdy_i) begin
          if (pre_q == 0 && mem_wrreq_i) begin
            wak_c = 1'b1;
            col_c = mem_wradr_i[CSB:0];
            pre_c = mem_wrlst_i ? PUNIT : PZERO;
            cmd_c = CMD_WRIT;
          end else begin
            wen_c = 1'b0;
            req_c = 1'b0;
            cmd_c = CMD_NOOP;
            snext = ST_IDLE;
          end
          adr_c = {pre_c, col_c};
        end
      end

      ST_READ: begin
        if (ddl_rdy_i) begin
          if (pre_q == 0 && mem_rdreq_i) begin
            rak_c = 1'b1;
            col_c = mem_rdadr_i[CSB:0];
            pre_c = mem_rdlst_i ? PUNIT : PZERO;
            cmd_c = CMD_READ;
          end else begin
            req_c = 1'b0;
            cmd_c = CMD_NOOP;
            snext = ST_IDLE;
          end
          adr_c = {pre_c, col_c};
        end
      end

      ST_REFR: begin
        if (!ddl_ref_i || ddl_rdy_i) begin
          req_c = 1'b0;
          cmd_c = CMD_NOOP;
          snext = ST_IDLE;
        end
      end
    endcase

    if (reset) begin
      adr_c = cfg_adr_i;
      {pre_c, col_c} = cfg_adr_i;
      ba_c = cfg_ba_i;
      wak_c = 1'b0;
      rak_c = 1'b0;
      cmd_c = cfg_cmd_i;
      req_c = cfg_req_i;
      wen_c = 1'b1;
      snext = ST_IDLE;
    end
  end

  always @(posedge clock or negedge arst_n) begin
    if (!arst_n) begin
      pre_q <= 0;
      wrack <= 1'b0;
      rdack <= 1'b0;
      cmd_q <= CMD_NOOP;
      req_q <= 1'b0;
      wen_q <= 1'b0;
      state <= ST_IDLE;
    end else begin
      adr_q <= adr_c;
      col_q <= col_c;
      ba_q  <= ba_c;
      pre_q <= pre_c;
      wrack <= wak_c;
      rdack <= rak_c;
      cmd_q <= cmd_c;
      req_q <= req_c;
      wen_q <= wen_c;
      state <= snext;
    end
  end

`ifdef __icarus
  //
  //  Simulation Only
  ///

  reg [39:0] dbg_state, dbg_snext;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = reset ? "INIT" : "IDLE";
      ST_READ: dbg_state = adr_q[10] ? "RD-A" : "RD";
      ST_WRIT: dbg_state = adr_q[10] ? "WR-A" : "WR";
      ST_ACTV: dbg_state = "ACT";
      ST_REFR: dbg_state = "REF";
      default: dbg_state = "XXX";
    endcase
    case (snext)
      ST_IDLE: dbg_snext = reset ? "INIT" : "IDLE";
      ST_READ: dbg_snext = adr_c[10] ? "RD-A" : "RD";
      ST_WRIT: dbg_snext = adr_c[10] ? "WR-A" : "WR";
      ST_ACTV: dbg_snext = "ACT";
      ST_REFR: dbg_snext = "REF";
      default: dbg_snext = "XXX";
    endcase
  end

  wire [ 2:0] dbg_cmd_w = ddl_rdy_i ? cmd_q : CMD_NOOP;
  reg  [39:0] dbg_cmd;

  always @* begin
    case (dbg_cmd_w)
      CMD_MODE: dbg_cmd = "MRS";
      CMD_REFR: dbg_cmd = "REF";
      CMD_PREC: dbg_cmd = adr_q[10] ? "PREA" : "PRE";
      CMD_ACTV: dbg_cmd = "ACT";
      CMD_WRIT: dbg_cmd = adr_q[10] ? "WR-A" : "WR";
      CMD_READ: dbg_cmd = adr_q[10] ? "RD-A" : "RD";
      CMD_ZQCL: dbg_cmd = "ZQCL";
      CMD_NOOP: dbg_cmd = "---";
      default:  dbg_cmd = "XXX";
    endcase
  end

`endif /* !__icarus */


endmodule  /* ddr3_fsm */

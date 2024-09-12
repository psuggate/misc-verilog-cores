`timescale 1ns / 100ps
/**
 * Issues DDR3 commands based on the read-request and write-request FIFO inputs.
 *
 * Specifics of DDR3 initialisation and timings are handled one level down, by
 * the "DFI" module. This module schedules row-activations, bank-precharging,
 * read-requests, and data-writes.
 */
module old_ddr3_fsm (
    arst_n,

    clock,
    reset,

    mem_wrreq_i,  // Write port
    mem_wrlst_i,
    mem_wrtid_i,
    mem_wradr_i,
    mem_wrack_o,
    mem_wrerr_o,

    mem_rdreq_i,  // Read port
    mem_rdlst_i,
    mem_rdtid_i,
    mem_rdadr_i,
    mem_rdack_o,
    mem_rderr_o,

    cfg_req_i,  // Configuration port
    cfg_rdy_o,
    cfg_cmd_i,
    cfg_ba_i,
    cfg_adr_i,

    ddl_req_o,
    ddl_seq_o,
    ddl_ref_i,
    ddl_rdy_i,
    ddl_cmd_o,
    ddl_ba_o,
    ddl_adr_o
);

  parameter NEXT_GEN_FSM = 1;

  // DDR3 SRAM Timings
  parameter DDR_FREQ_MHZ = 100;
  `include "ddr3_settings.vh"

  // If enabled, the {wrlst, rdlst} are used to decide when to ACTIVATE and
  // PRECHARGE rows
  // todo:
  parameter WRLAST_ENABLE = 1'b1;
  parameter RDLAST_ENABLE = 1'b1;

  // Request ID's are represent the order that commands are accepted at the bus/
  // transaction layer, and if used, the memory controller will respect this
  // ordering, when reads and writes access overlapping areas of memory.
  parameter REQID = 4;
  localparam ISB = REQID - 1;

  // Defaults for 1Gb, 16x SDRAM
  parameter DDR_ROW_BITS = 13;
  localparam RSB = DDR_ROW_BITS - 1;
  parameter DDR_COL_BITS = 10;
  localparam CSB = DDR_COL_BITS - 1;

  // Default is '{row, bank, col} <= addr_i;' -- this affects how often banks will
  // need PRECHARGE commands. Enabling this alternate {bank, row, col} ordering
  // may help for some workloads; e.g., when all but the upper (burst) addresses
  // are not correlated in time?
  // todo: ...
  parameter BANK_ROW_COL = 0;

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
  parameter ADDRS = 23;
  localparam ASB = ADDRS - 1;

  input arst_n;  // Global, asynchronous reset

  input clock;  // Shared clock domain for the memory-controller
  input reset;  // Synchronous reset

  // Write-request port
  input mem_wrreq_i;
  input mem_wrlst_i;  // If asserted, then LAST of burst
  output mem_wrack_o;
  output mem_wrerr_o;
  input [ISB:0] mem_wrtid_i;
  input [ASB:0] mem_wradr_i;

  // Read-request port
  input mem_rdreq_i;
  input mem_rdlst_i;  // If asserted, then LAST of burst
  output mem_rdack_o;
  output mem_rderr_o;
  input [ISB:0] mem_rdtid_i;
  input [ASB:0] mem_rdadr_i;

  // Configuration port
  input cfg_req_i;
  output cfg_rdy_o;
  input [2:0] cfg_cmd_i;
  input [2:0] cfg_ba_i;
  input [RSB:0] cfg_adr_i;

  // DDR Data-Layer control signals
  // Note: all state-transitions are gated by the 'ddl_rdy_i' signal
  output ddl_req_o;
  output ddl_seq_o;
  input ddl_rdy_i;
  input ddl_ref_i;
  output [2:0] ddl_cmd_o;
  output [2:0] ddl_ba_o;
  output [RSB:0] ddl_adr_o;

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

  // Todo: Relative transaction costs, for scoring and scheduling ??
  parameter COST_RD_TO_RD = 2;
  parameter COST_WR_TO_WR = 2;
  parameter COST_RD_TO_WR = 3;
  parameter COST_WR_TO_RD = 7;

  localparam ADR_PAD_BITS = DDR_ROW_BITS - DDR_COL_BITS - 1;

  // DDR3 controller states
  // todo: effectively there are only three states, so refactor ...
  localparam [4:0] ST_IDLE = 5'b10000;
  localparam [4:0] ST_READ = 5'b01000;
  localparam [4:0] ST_WRIT = 5'b00100;
  localparam [4:0] ST_ACTV = 5'b00010;
  localparam [4:0] ST_REFR = 5'b00001;

  reg req_q, req_x, req_s;
  reg [2:0] cmd_q, cmd_x, ba_q;
  reg [RSB:0] adr_q, adr_x;

  wire auto_w, refresh;
  wire [RSB:0] row_w, col_w;
  wire [2:0] bank_w;
  wire [RSB:0] wrcol, rdcol, adr_w;

  reg wrack, rdack;
  reg [4:0] state, snext;
  wire store_w, fetch_w;


  // -- Next-Generation FSM Settings, Signals, and Registers -- //

  // Todo: does not handle the x4 SDRAMs
  localparam PBITS = DDR_ROW_BITS - DDR_COL_BITS;
  localparam PZERO = {PBITS{1'b0}};
  localparam PUNIT = {{PSB{1'b0}}, 1'b1};
  localparam PSB = PBITS - 1;

  reg [4:0] sta_c, sta_q;
  reg [RSB:0] adr_c, adr_r, row_c, row_q;
  reg [CSB:0] col_c, col_q;
  reg [2:0] ba_c, ba_r, cmd_c, cmd_r;
  reg [PSB:0] pre_c, pre_q;
  reg wak_c, wak_q, rak_c, rak_q, req_c, req_r, wen_c, wen_q;

  assign cfg_rdy_o = ddl_rdy_i;

  assign mem_wrack_o = NEXT_GEN_FSM ? wak_q : wrack;
  assign mem_wrerr_o = 1'b0;
  assign mem_rdack_o = NEXT_GEN_FSM ? rak_q : rdack;
  assign mem_rderr_o = 1'b0;

  assign ddl_req_o = NEXT_GEN_FSM ? req_r : req_q;
  assign ddl_seq_o = NEXT_GEN_FSM ? (pre_q == 0) : req_x;
  assign ddl_cmd_o = NEXT_GEN_FSM ? cmd_r : cmd_q;
  assign ddl_ba_o = NEXT_GEN_FSM ? ba_r : ba_q;
  assign ddl_adr_o = NEXT_GEN_FSM ? adr_r : adr_q;

  // -- Next-Generation FSM Logics -- //

  always @* begin
    adr_c = adr_r;
    col_c = col_q;
    ba_c  = ba_r;
    pre_c = pre_q;
    wak_c = 1'b0;
    rak_c = 1'b0;
    cmd_c = cmd_r;
    req_c = req_r;
    wen_c = wen_q;
    sta_c = sta_q;

    case (sta_q)
      ST_IDLE: begin
        wen_c = 1'b0;
        if (ddl_ref_i) begin
          req_c = 1'b1;
          pre_c = PUNIT;
          adr_c = {pre_c, col_c};
          cmd_c = CMD_REFR;
          sta_c = ST_REFR;
        end else if (mem_rdreq_i) begin
          {adr_c, ba_c, col_c} = mem_rdadr_i;
          req_c = 1'b1;
          pre_c = mem_rdlst_i ? PUNIT : PZERO;
          rak_c = 1'b1;
          wen_c = 1'b0;
          cmd_c = CMD_ACTV;
          sta_c = ST_ACTV;
        end else if (mem_wrreq_i) begin
          {adr_c, ba_c, col_c} = mem_wradr_i;
          req_c = 1'b1;
          pre_c = mem_wrlst_i ? PUNIT : PZERO;
          wak_c = 1'b1;
          wen_c = 1'b1;
          cmd_c = CMD_ACTV;
          sta_c = ST_ACTV;
        end
      end

      ST_ACTV: begin
        if (ddl_rdy_i) begin
          adr_c = {pre_q, col_q};
          cmd_c = wen_q ? CMD_WRIT : CMD_READ;
          sta_c = wen_q ? ST_WRIT : ST_READ;
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
            sta_c = ST_IDLE;
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
            sta_c = ST_IDLE;
          end
          adr_c = {pre_c, col_c};
        end
      end

      ST_REFR: begin
        if (!ddl_ref_i || ddl_rdy_i) begin
          req_c = 1'b0;
          cmd_c = CMD_NOOP;
          sta_c = ST_IDLE;
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
      sta_c = ST_IDLE;
    end
  end

  always @(posedge clock or negedge arst_n) begin
    if (!arst_n) begin
      pre_q <= 0;
      wak_q <= 1'b0;
      rak_q <= 1'b0;
      cmd_r <= CMD_NOOP;
      req_r <= 1'b0;
      wen_q <= 1'b0;
      sta_q <= ST_IDLE;
    end else begin
      adr_r <= adr_c;
      col_q <= col_c;
      ba_r  <= ba_c;
      pre_q <= pre_c;
      wak_q <= wak_c;
      rak_q <= rak_c;
      cmd_r <= cmd_c;
      req_r <= req_c;
      wen_q <= wen_c;
      sta_q <= sta_c;
    end
  end

  // -- Address Logic -- //

  wire wrsel;
  wire [1:0] asel;

  assign asel = reset ? 2'b11 : req_x ? 2'b00 : mem_rdreq_i ? 2'b01 : mem_wrreq_i ? 2'b10 : 2'b00;

  assign row_w  = asel == 2'b11 ? cfg_adr_i
                : asel == 2'b10 ? mem_wradr_i[ASB:DDR_COL_BITS + 3]
                : asel == 2'b01 ? mem_rdadr_i[ASB:DDR_COL_BITS + 3]
                : adr_x ;

  assign bank_w = asel == 2'b11 ? cfg_ba_i
                : asel == 2'b10 ? mem_wradr_i[DDR_COL_BITS + 2:DDR_COL_BITS]
                : asel == 2'b01 ? mem_rdadr_i[DDR_COL_BITS + 2:DDR_COL_BITS]
                : ba_q ;

  // Determines the next value of 'adr_x'
  assign wrcol = {{ADR_PAD_BITS{1'b0}}, mem_wrreq_i & mem_wrlst_i, mem_wradr_i[CSB:0]};
  assign rdcol = {{ADR_PAD_BITS{1'b0}}, mem_rdreq_i & mem_rdlst_i, mem_rdadr_i[CSB:0]};
  assign wrsel = (state != ST_IDLE && store_w) || mem_wrreq_i && !mem_rdreq_i;
  assign adr_w = wrsel ? wrcol : rdcol;

  // -- Main State Machine -- //

  assign refresh = ddl_ref_i;

  assign store_w = snext[2];
  assign fetch_w = snext[3];

  always @(posedge clock) begin
    if (reset) begin
      // Forward the initialisation and configuration commands on to the DFI,
      // until the configuration module asserts 'reset'.
      state <= ST_IDLE;
      snext <= ST_IDLE;
      req_q <= cfg_req_i;
      cmd_q <= cfg_cmd_i;
      ba_q  <= bank_w;
      adr_q <= row_w;
      req_x <= 1'b0;
      cmd_x <= CMD_NOOP;
      adr_x <= {DDR_ROW_BITS{1'bx}};
      req_s <= 1'b0;
      wrack <= 1'b0;
      rdack <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          // Wait for read-/write- requests -- refreshing, as required
          req_q <= refresh | mem_rdreq_i | mem_wrreq_i;
          ba_q  <= bank_w;
          adr_q <= row_w;
          adr_x <= adr_w;

          if (!refresh && (mem_rdreq_i || mem_wrreq_i)) begin
            state <= ST_ACTV;
            snext <= mem_rdreq_i ? ST_READ : ST_WRIT;
            cmd_q <= CMD_ACTV;
            req_x <= 1'b1;
            cmd_x <= mem_rdreq_i ? CMD_READ : CMD_WRIT;
            req_s <= (mem_rdreq_i & ~mem_rdlst_i) |  // Sequence of BL8 ops ??
            (mem_wrreq_i & ~mem_rdreq_i & ~mem_wrlst_i);
            wrack <= ~mem_rdreq_i & mem_wrreq_i;
            rdack <= mem_rdreq_i;
          end else begin
            // Note: we do not 'IDLE' with 'ACTIVE' banks
            state <= refresh ? ST_REFR : ST_IDLE;
            snext <= ST_IDLE;
            cmd_q <= refresh ? CMD_REFR : CMD_NOOP;
            req_x <= 1'b0;
            cmd_x <= CMD_NOOP;
            req_s <= 1'b0;
            wrack <= 1'b0;
            rdack <= 1'b0;
          end
        end

        ST_ACTV, ST_WRIT, ST_READ: begin
          ba_q  <= ba_q;  // note: return to 'IDLE' to bank-switch

          wrack <= ~wrack & ddl_rdy_i & req_s & store_w & mem_wrreq_i;
          rdack <= ~rdack & ddl_rdy_i & req_s & fetch_w & mem_rdreq_i;

          if (ddl_rdy_i) begin
            state <= snext;
            req_q <= req_x;
            cmd_q <= cmd_x;
            adr_q <= row_w;

            // Command issued, issue another as part of a sequence?
            if (!req_s) begin
              snext <= ST_IDLE;
              req_x <= 1'b0;
              cmd_x <= CMD_NOOP;
              adr_x <= adr_x;
              req_s <= 1'b0;
            end else if (store_w && mem_wrreq_i || fetch_w && mem_rdreq_i) begin
              snext <= snext;
              req_x <= req_x;
              cmd_x <= cmd_x;
              adr_x <= adr_w;
              req_s <= (store_w & mem_wrreq_i & ~mem_wrlst_i) |
                       (fetch_w & mem_rdreq_i & ~mem_rdlst_i) ;
            end else begin
              // todo: this should just be a 'WAIT' ??
              $error("%10t: Unimplemented", $time);
              snext <= snext;
              req_x <= req_x;
              cmd_x <= cmd_x;
              adr_x <= adr_x;
              req_s <= req_s;
              // #100 $fatal;
            end
          end else begin
            state <= state;
            snext <= snext;
            req_q <= req_q;
            cmd_q <= cmd_q;
            adr_q <= adr_q;
            req_x <= req_x;
            cmd_x <= cmd_x;
            adr_x <= adr_x;
            req_s <= req_s;
          end
        end

        ST_REFR: begin
          snext <= ST_IDLE;
          ba_q  <= ba_q;  // note: return to 'IDLE' to bank-switch

          req_x <= req_x;
          cmd_x <= cmd_x;
          adr_x <= adr_x;
          req_s <= 1'b0;

          // Wait for all outstanding REFRESH operations to complete
          // Note: 'ddl_ref_i' stays asserted until REFRESH is about to finish
          if (!ddl_ref_i || ddl_rdy_i) begin
            state <= snext;
            req_q <= req_x;
            cmd_q <= cmd_x;
            adr_q <= row_w;
          end else begin
            state <= state;
            req_q <= req_q;
            cmd_q <= cmd_q;
            adr_q <= adr_q;
          end

          wrack <= 1'b0;
          rdack <= 1'b0;
        end

        default: begin
          $error("Oh noes");
          state <= ST_IDLE;
          snext <= ST_IDLE;

          req_q <= cfg_req_i;
          cmd_q <= cfg_cmd_i;
          ba_q  <= bank_w;
          adr_q <= row_w;

          req_x <= 1'b0;
          cmd_x <= CMD_NOOP;
          adr_x <= {DDR_ROW_BITS{1'bx}};
          req_s <= 1'b0;

          wrack <= 1'b0;
          rdack <= 1'b0;
          // #100 $fatal;
        end
      endcase
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus
  reg [39:0] dbg_state, dbg_snext;
  wire [4:0] sta_w = NEXT_GEN_FSM ? sta_q : state;

  always @* begin
    case (sta_w)
      ST_IDLE: dbg_state = reset ? "INIT" : "IDLE";
      ST_READ: dbg_state = adr_q[10] ? "RD-A" : "RD";
      ST_WRIT: dbg_state = adr_q[10] ? "WR-A" : "WR";
      ST_ACTV: dbg_state = "ACT";
      ST_REFR: dbg_state = "REF";
      default: dbg_state = "XXX";
    endcase
    case (snext)
      ST_IDLE: dbg_snext = reset ? "INIT" : "IDLE";
      ST_READ: dbg_snext = adr_q[10] ? "RD-A" : "RD";
      ST_WRIT: dbg_snext = adr_q[10] ? "WR-A" : "WR";
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
`endif


endmodule  /* old_ddr3_fsm */

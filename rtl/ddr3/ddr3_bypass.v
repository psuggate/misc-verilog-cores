`timescale 1ns / 100ps
/**
 * Read-only fast-path AXI4 interface to the memory controller. Bypasses the
 * ordinary address- and data- paths, for lower-latency reads.
 *
 * Note:
 *  - BOTH 'axi_arvalid_i' AND 'axi_rready_i' need to be asserted, to begin a
 *    fast-path read -- you will need to add an output FIFO if otherwise you
 *    cannot guarantee that the read-data will be accepted (without wait-
 *    states);
 *  - intended for low-latency, high-priority reads; e.g., to service fetch-
 *    requests from a processor (i.e., to fetch a cache-line for one of its
 *    caches);
 *  - handles only a subset of the SDRAM functionality;
 *  - throws an exception if the requesting core does not accept the returned
 *    read-data in time (so 'axi_rready_i' should be asserted, and held, until
 *    the transaction completes);
 *  - address alignment must be correct, and the AXI4 burst-size must be BL8;
 */
module ddr3_bypass #(
    // DDR3 SRAM Timings
    parameter DDR_FREQ_MHZ = 100,

    parameter BYPASS_ENABLE = 1'b1,

    // Data-path and address settings
    parameter  WIDTH = 32,
    localparam MSB   = WIDTH - 1,

    parameter  MASKS = WIDTH / 8,
    localparam SSB   = MASKS - 1,

    // Request ID's are represent the order that commands are accepted at the bus/
    // transaction layer, and if used, the memory controller will respect this
    // ordering, when reads and writes access overlapping areas of memory.
    parameter  REQID = 4,
    localparam ISB   = REQID - 1,

    // Defaults for 1Gb, 16x SDRAM
    parameter DDR_ROW_BITS = 13,
    localparam RSB = DDR_ROW_BITS - 1,
    parameter DDR_COL_BITS = 10,
    localparam CSB = DDR_COL_BITS - 1,
    localparam ADR_PAD_BITS = DDR_ROW_BITS - DDR_COL_BITS - 1,

    // Default is '{row, bank, col} <= addr_i,' -- this affects how often banks will
    // need PRECHARGE commands. Enabling this alternate {bank, row, col} ordering
    // may help for some workloads, e.g., when all but the upper (burst) addresses
    // are not correlated in time?
    // todo: ...
    parameter BANK_ROW_COL = 0,

    // Note: all addresses for requests must be word- and burst- aligned. Therefore,
    //   for a x16 DDR3 device, each transfer is 16 bytes, so the lower 4-bits are
    //   not passed to this controller.
    // Note: a 1Gb, x16, DDR3 SDRAM has:
    //    - 13b row address bits,
    //    -  3b bank address bits,
    //    - 10b column address bits, and
    //    - 2kB page-size,
    //   and the lower 3b of the column address are ignored by this module. So a 23b
    //   address is required.
    // Todo: in order to support wrapping-bursts, e.g., for a CPU cache, will need
    //   the lower 3b ??
    parameter  ADDRS = 23,
    localparam ASB   = ADDRS - 1
) (
    input clock,  // Shared clock domain for the memory-controller
    input reset,  // Synchronous reset

    // AXI4 Fast-Read-Path Address Port
    input axi_arvalid_i,
    output axi_arready_o,
    input [ASB:0] axi_araddr_i,
    input [ISB:0] axi_arid_i,
    input [7:0] axi_arlen_i,
    input [1:0] axi_arburst_i,

    // AXI4 Fast-Read-Path Data Port
    input axi_rready_i,
    output axi_rvalid_o,
    output [MSB:0] axi_rdata_o,
    output [1:0] axi_rresp_o,
    output [ISB:0] axi_rid_o,
    output axi_rlast_o,

    // DDL READ data-path
    input ddl_rvalid_i,
    output ddl_rready_o,
    input ddl_rlast_i,
    input [MSB:0] ddl_rdata_i,

    // DDR Data-Layer control signals
    // Note: 
    //  - all state-transitions are gated by the 'byp_rdy_i' signal
    //   - connects to the DDL
    input byp_run_i,
    output byp_req_o,
    output byp_seq_o,
    input byp_rdy_i,
    input byp_ref_i,
    output [2:0] byp_cmd_o,
    output [2:0] byp_ba_o,
    output [RSB:0] byp_adr_o,

    // From/to DDR3 Controller
    // Note:
    //  - all state-transitions are gated by the 'ctl_rdy_o' signal
    //  - intercepts these memory controller -> DDL signals
    output ctl_run_o,
    input ctl_req_i,
    input ctl_seq_i,  // Todo: burst-sequence indicator ...
    output ctl_rdy_o,
    output ctl_ref_o,
    input [2:0] ctl_cmd_i,
    input [2:0] ctl_ba_i,
    input [RSB:0] ctl_adr_i,

    // READ data from DDL -> memory controller data-path
    output ctl_rvalid_o,
    input ctl_rready_i,
    output ctl_rlast_o,
    output [MSB:0] ctl_rdata_o
);

  //
  // Todo:
  //  1. ~~disabled-mode works~~
  //  2. ~~enabled-mode and no bypass-requests works~~
  //  3. works as read-only, single-BL8 AXI4 interface (ignores slow-path requests)
  //  4. multi-BL8 reads
  //  5. row & bank detection ??
  //

  // -- Constants -- //

  `include "ddr3_settings.vh"
  `include "axi_defs.vh"

  // Subset of DDR3 controller commands/states
  localparam [2:0] ST_IDLE = 3'b111;
  localparam [2:0] ST_READ = 3'b101;
  localparam [2:0] ST_ACTV = 3'b011;
  localparam [2:0] ST_PREC = 3'b010;

  // -- Internal Signals & State -- //

  reg arack, req_q, rdy_q;
  reg [2:0] cmd_q, ba_q;
  reg [RSB:0] adr_q, adr_x;

  wire asel_w, auto_w, bypass, precharge_w, fast_read_w;
  wire [2:0] ba_w, bank_w, cmd_w;
  wire [RSB:0] row_w, col_w, adr_w;
  wire [CSB:0] col_l;

  reg autop, active_q;
  reg [RSB:0] actv_row;
  reg [  2:0] actv_ba;

  reg [3:0] state, snext;
  reg burst;

  // Don't drive the AXI4 interface (in-case it is connected)
  assign axi_arready_o = BYPASS_ENABLE ? arack : 1'b0;

  assign axi_rvalid_o = BYPASS_ENABLE ? rdy_q & ddl_rvalid_i : 1'b0;
  assign axi_rlast_o  = BYPASS_ENABLE ? ddl_rlast_i : 1'b0;
  assign axi_rresp_o  = BYPASS_ENABLE ? RESP_OKAY : 2'bx;
  assign axi_rid_o    = BYPASS_ENABLE ? axi_arid_i : {REQID{1'bx}};
  assign axi_rdata_o  = BYPASS_ENABLE ? ddl_rdata_i : {WIDTH{1'bx}};

  assign ddl_rready_o = ctl_rready_i | (BYPASS_ENABLE & rdy_q & axi_rready_i);

  generate
    if (BYPASS_ENABLE) begin : g_bypass

      initial begin
        $error("Not yet functional");
        #10 $fatal;
      end

      // -- Use the Bypass Port -- //

      assign ctl_rvalid_o = ~rdy_q & ddl_rvalid_i;
      assign ctl_rlast_o = req_q ? 1'bx : ddl_rlast_i;
      assign ctl_rdata_o = req_q ? {WIDTH{1'bx}} : ddl_rdata_i;

      assign byp_req_o = bypass | ctl_req_i;
      assign byp_seq_o = bypass ? 1'b0 : ctl_seq_i;  // todo
      assign byp_cmd_o = cmd_w;
      assign byp_ba_o = ba_w;
      assign byp_adr_o = adr_w;

      assign ctl_rdy_o = bypass ? 1'b0 : byp_rdy_i;  // todo
      assign ctl_ref_o = byp_ref_i;

    end else begin : g_normal

      // -- Bypass is Disabled -- //

      // Forward all signals directly to/from the memory controller
      assign ctl_run_o = byp_run_i;
      assign ctl_rdy_o = byp_rdy_i;
      assign ctl_ref_o = byp_ref_i;

      assign byp_req_o = ctl_req_i;
      assign byp_seq_o = ctl_seq_i;
      assign byp_cmd_o = ctl_cmd_i;
      assign byp_ba_o = ctl_ba_i;
      assign byp_adr_o = ctl_adr_i;

      assign ctl_rvalid_o = ddl_rvalid_i;
      assign ctl_rlast_o = ddl_rlast_i;
      assign ctl_rdata_o = ddl_rdata_i;

    end
  endgenerate

  assign bypass = axi_arvalid_i & arack | req_q;

  assign precharge_w = axi_arvalid_i && arack && active_q && bank_w == actv_ba && row_w != actv_row;
  assign fast_read_w = axi_arvalid_i && arack && active_q && bank_w == actv_ba && row_w == actv_row;

  // assign cmd_w  = state == ST_IDLE ? CMD_ACTV : cmd_q;
  assign cmd_w = req_q ? cmd_q
               : ~axi_arvalid_i | ~arack ? ctl_cmd_i
               : precharge_w ? CMD_PREC
               : fast_read_w ? CMD_READ
               : CMD_ACTV ;

  // -- Address Logic -- //

  // Output address & select
  assign asel_w = axi_arvalid_i & axi_arready_o;
  assign ba_w = asel_w ? bank_w : req_q ? ba_q : ctl_ba_i;
  assign adr_w = asel_w ? row_w : req_q ? adr_q : ctl_adr_i;

  // AUTO-PRECHARGE bit
  // todo: gonna have to detect sequences ourselves ...
  assign auto_w = axi_arvalid_i && axi_arburst_i == 2'b01 && axi_arlen_i == 8'd3;

  // Bypass-address capture
  assign bank_w = axi_araddr_i[DDR_COL_BITS+2:DDR_COL_BITS];
  assign row_w = axi_araddr_i[ASB:DDR_COL_BITS+3];
  assign col_w = {{ADR_PAD_BITS{1'b0}}, auto_w, axi_araddr_i[CSB:0]};

  // -- PRECHARGE Detection -- //

  // If bypass request address requires a different ROW within the currently-
  // ACTIVE BANK, then we need to PRECHARGE, then re-ACTIVATE that same BANK
  // after the fast-path READ completes.

  always @(posedge clock) begin
    if (reset) begin
      autop <= 1'b0;
    end else begin
      autop <= autop;
    end
  end

  // Track the currently-ACTIVE ROW & BANK.
  // Note: assumes that the memory controller only ever has one bank ACTIVE.
  // todo: is this robust enough ??

  always @(posedge clock) begin
    if (reset) begin
      active_q <= 1'b0;
      actv_ba  <= 3'bx;
      actv_row <= {DDR_ROW_BITS{1'bx}};
    end else if (ctl_req_i && byp_rdy_i) begin
      case (ctl_cmd_i)
        CMD_ACTV: begin
          active_q <= 1'b1;
          actv_ba  <= ctl_ba_i;
          actv_row <= ctl_adr_i;
        end

        CMD_READ, CMD_WRIT: begin
          if (ctl_adr_i[10]) begin
            active_q <= 1'b0;
            actv_ba  <= 3'bx;
            actv_row <= {DDR_ROW_BITS{1'bx}};
          end else begin
            active_q <= active_q;
            actv_ba  <= actv_ba;
            actv_row <= actv_row;
          end
        end

        CMD_PREC: begin
          active_q <= 1'b0;
          actv_ba  <= 3'bx;
          actv_row <= {DDR_ROW_BITS{1'bx}};
        end

        default: begin
          active_q <= active_q;
          actv_ba  <= actv_ba;
          actv_row <= actv_row;
        end
      endcase
    end
  end

  // -- Burst-Sequence Detection -- //

  // For AXI4 incrementing bursts, perform multiple, sequential (DDR3 SDRAM) BL8
  // reads.
  // todo: ...

  always @(posedge clock) begin
    if (reset) begin
      burst <= 1'b0;
    end else if (axi_arvalid_i && axi_rready_i) begin
      burst <= axi_arlen_i > 3 && axi_arburst_i == BURST_TYPE_INCR;
    end else if (axi_rvalid_o && axi_rready_i && axi_rlast_o) begin
      burst <= 1'b0;
    end else begin
      burst <= burst;
    end
  end

  // -- Main State Machine -- //

  //
  // Todo:
  //  - detect same bank+row, for subsequent commands
  //     + long-bursts that cross page boundaries ?
  //     + "coalesce" reads and/or writes to same pages ?
  //  - auto-precharge when required
  //  - track the active row for each bank
  //  - overflow registers for when commands are accepted on both inputs
  //  - implement address-bits -> bank selection
  //

  always @(posedge clock) begin
    if (!byp_run_i) begin
      // Forward the initialisation and configuration commands on to the DFI,
      // until the configuration module asserts 'reset'.
      state <= ST_IDLE;
      req_q <= 1'b0;
      cmd_q <= 3'bx;
      ba_q  <= 3'bx;
      adr_q <= {DDR_ROW_BITS{1'bx}};
      adr_x <= {DDR_ROW_BITS{1'bx}};
      arack <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          // Wait for read-/write- requests -- refreshing, as required
          req_q <= axi_arvalid_i & arack;
          ba_q  <= bank_w;
          adr_q <= byp_rdy_i ? col_w : row_w;
          adr_x <= col_w;

          if (axi_arvalid_i && arack) begin
            if (byp_rdy_i) begin
              state <= ST_READ;
              cmd_q <= CMD_READ;
            end else begin
              state <= ST_ACTV;
              cmd_q <= CMD_ACTV;
            end
            arack <= 1'b0;
          end else begin
            state <= ST_IDLE;
            cmd_q <= CMD_NOOP;
            arack <= axi_rready_i;
          end
        end

        ST_ACTV: begin
          req_q <= 1'b1;
          ba_q  <= ba_q;  // note: return to 'IDLE' to bank-switch
          adr_x <= adr_x;

          if (byp_rdy_i) begin
            state <= ST_READ;
            cmd_q <= CMD_READ;
            adr_q <= adr_x;
          end else begin
            state <= ST_ACTV;
            cmd_q <= CMD_ACTV;
            adr_q <= adr_q;
          end

          arack <= 1'b0;
        end

        ST_READ: begin
          adr_x <= {DDR_ROW_BITS{1'bx}};

          if (byp_rdy_i) begin
            req_q <= 1'b0;
            cmd_q <= CMD_NOOP;
            ba_q  <= 3'bx;
            adr_q <= {DDR_ROW_BITS{1'bx}};  // row_w;
          end else begin
            req_q <= req_q;
            cmd_q <= cmd_q;
            ba_q  <= ba_q;
            adr_q <= adr_q;
          end

          if (axi_rvalid_o && axi_rready_i && axi_rlast_o) begin
            state <= ST_IDLE;
          end else begin
            state <= ST_READ;
          end

          arack <= 1'b0;
        end

        default: begin
          $error("Oh noes");
          state <= ST_IDLE;
          req_q <= 1'b0;
          cmd_q <= 3'bx;
          ba_q  <= 3'bx;
          adr_q <= {DDR_ROW_BITS{1'bx}};
          adr_x <= {DDR_ROW_BITS{1'bx}};
          arack <= 1'b0;
          // #100 $fatal;
        end
      endcase
    end
  end

  always @(posedge clock) begin
    if (reset || ddl_rvalid_i && rdy_q && ddl_rlast_i) begin
      rdy_q <= 1'b0;
    end else if (req_q && byp_rdy_i) begin
      rdy_q <= 1'b1;
    end
  end


`ifdef __icarus
  //
  //  Simulation Only
  ///

  reg [39:0] dbg_state, dbg_snext, dbg_cmd;
  wire [2:0] dbg_cmd_w;

  always @(posedge clock or posedge reset) begin
    if (!reset && axi_arvalid_i && axi_arready_o) begin
      if (axi_arburst_i != 2'b01) begin
        $error("%10t: Only AXI4 INCR bursts are supported (BURST = %1d)", $time, axi_arburst_i);
      end
      if (axi_arlen_i != 8'h03) begin
        $error("%10t: Only AXI4 4x32b bursts are supported (LEN = %1d)", $time, axi_arlen_i);
      end
    end
  end

  always @* begin
    case (state)
      ST_IDLE: dbg_state = !reset ? "IDLE" : "INIT";
      ST_READ: dbg_state = adr_q[10] ? "RD-A" : "RD";
      ST_PREC: dbg_state = "PREC";
      ST_ACTV: dbg_state = "ACT";
      default: dbg_state = "XXX";
    endcase
    case (snext)
      ST_IDLE: dbg_snext = !reset ? "IDLE" : "INIT";
      ST_READ: dbg_snext = adr_q[10] ? "RD-A" : "RD";
      ST_PREC: dbg_snext = "PREC";
      ST_ACTV: dbg_snext = "ACT";
      default: dbg_snext = "XXX";
    endcase
  end

  assign dbg_cmd_w = byp_rdy_i ? cmd_q : CMD_NOOP;

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

`endif  /* !__icarus */

endmodule  /* ddr3_bypass */

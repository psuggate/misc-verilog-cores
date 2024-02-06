`timescale 1ns / 100ps
/**
 * DDR3 "Data-Link" layer converts simple memory-controller commands into DFI
 * commands.
 *
 * Notes:
 *  - handles device- and mode- specific timings;
 *  - no flow-control, nor buffering -- as this belongs at higher layers;
 *  - assumes that the memory controller and the AXI4 bus are within the same
 *    clock-domain;
 *
 * Copyright 2023, Patrick Suggate.
 *
 */
module ddr3_ddl (
    clock,
    reset,

    ddr_cke_i,
    ddr_cs_ni,

    ctl_run_o,  // Memory controller signals
    ctl_req_i,
    ctl_seq_i,
    ctl_rdy_o,
    ctl_cmd_i,
    ctl_ba_i,
    ctl_adr_i,

    mem_wvalid_i,  // WRITE data-path
    mem_wready_o,
    mem_wlast_i,
    mem_wrmask_i,
    mem_wrdata_i,

    mem_rvalid_o,  // READ data-path
    mem_rready_i,
    mem_rlast_o,
    mem_rddata_o,

    dfi_ras_no,  // DDL <-> PHY signals
    dfi_cas_no,
    dfi_we_no,
    dfi_odt_o,
    dfi_bank_o,
    dfi_addr_o,
    dfi_wstb_o,
    dfi_wren_o,
    dfi_mask_o,
    dfi_data_o,
    dfi_rden_o,
    dfi_rvld_i,
    dfi_last_i,
    dfi_data_i
);

  //
  //  DDL Settings
  ///

  // -- DDR3 SDRAM Timings and Parameters -- //

  parameter DDR_FREQ_MHZ = 100;
  `include "ddr3_settings.vh"

  // Trims an additional clock-cycle of latency, if '1'
  parameter LOW_LATENCY = 1'b1;  // 0 or 1

  // Uses an the 'wr_strob' signal to clock out the WRITE data from the upstream
  // FIFO, when enabled (vs. the 'wr_ready' signal, which has one more cycle of
  // delay).
  // Note: the 'gw2a_ddr3_phy' requires this to be enabled
  parameter WR_PREFETCH = 1'b0;

  // Data-path and address settings
  parameter DDR_ROW_BITS = 13;
  localparam RSB = DDR_ROW_BITS - 1;

  parameter DDR_COL_BITS = 10;
  localparam CSB = DDR_COL_BITS - 1;

  parameter DFI_DQ_WIDTH = 32;
  localparam MSB = DFI_DQ_WIDTH - 1;

  parameter DFI_DM_WIDTH = DFI_DQ_WIDTH / 8;
  localparam SSB = DFI_DM_WIDTH - 1;


  // -- PHY Settings -- //

  // Note: these latencies are due to the registers and IOBs in the PHY for the
  //   commands, addresses, and the data-paths.
  parameter PHY_WR_DELAY = 1;
  parameter PHY_RD_DELAY = 1;

  localparam [WSB:0] WR_SHIFTS = DDR_CWL - PHY_WR_DELAY - LOW_LATENCY - 2;
  localparam [WSB:0] RD_SHIFTS = DDR_CL + PHY_RD_DELAY - LOW_LATENCY - 4;

  // A DDR3 burst has length of 8 transfers (DDR), so four clock/memory cycles
  // todo: ...
  localparam PHY_BURST_LEN = 4;


  input clock;
  input reset;

  input ddr_cke_i;
  input ddr_cs_ni;

  // From/to DDR3 Controller
  // Note: all state-transitions are gated by the 'ctl_rdy_o' signal
  output ctl_run_o;
  input ctl_req_i;
  input ctl_seq_i;  // Burst-sequence indicator
  output ctl_rdy_o;
  input [2:0] ctl_cmd_i;
  input [2:0] ctl_ba_i;
  input [RSB:0] ctl_adr_i;


  // AXI4-ish write and read ports (in order to de-/en- queue data from/to FIFOs,
  // efficiently)
  input mem_wvalid_i;  // Write port
  output mem_wready_o;
  input mem_wlast_i;  // todo: a good idea ??
  input [SSB:0] mem_wrmask_i;
  input [MSB:0] mem_wrdata_i;

  output mem_rvalid_o;  // Read port
  input mem_rready_i;
  output mem_rlast_o;  // todo: a good idea ??
  output [MSB:0] mem_rddata_o;

  // (Pseudo-) DDR3 PHY Interface (-ish)
  output dfi_ras_no;
  output dfi_cas_no;
  output dfi_we_no;
  output dfi_odt_o;
  output [2:0] dfi_bank_o;
  output [RSB:0] dfi_addr_o;

  output dfi_wstb_o;
  output dfi_wren_o;
  output [SSB:0] dfi_mask_o;
  output [MSB:0] dfi_data_o;

  output dfi_rden_o;
  input dfi_rvld_i;
  input dfi_last_i;
  input [MSB:0] dfi_data_i;


  // -- Constants -- //

  localparam DELAY = CYCLES_CKE_TO_CMD + 1;
  localparam DSB = DELAY - 1;
  localparam DZERO = {DELAY{1'b0}};
  localparam DINIT = 1 << (CYCLES_CKE_TO_CMD - 1);

  localparam CBITS = $clog2(DDR_CZQINIT);
  localparam XSB = CBITS - 1;
  localparam CZERO = {CBITS{1'b0}};

  localparam WDLYS = 4;  // BL8 = 4 extra delays
  localparam WSB = WDLYS - 1;

  // Delays for the various transitions
  localparam DELAY_CKE_TO_CMD = 1 << (CYCLES_CKE_TO_CMD - 1);
  localparam DELAY_MRD_TO_CMD = 1 << (CYCLES_MRD_TO_CMD - 1);
  localparam DELAY_PRE_TO_ACT = 1 << (CYCLES_PRE_TO_ACT - 1);
  localparam DELAY_ACT_TO_PRE = 1 << (CYCLES_ACT_TO_PRE - 1);
  localparam DELAY_REF_TO_ACT = 1 << (CYCLES_REF_TO_ACT - 2);
  localparam DELAY_ACT_TO_REF = 1 << (CYCLES_ACT_TO_REF - 1);

  localparam DELAY_ACT_TO_ACT_L = 1 << (CYCLES_ACT_TO_ACT - 1);
  localparam DELAY_ACT_TO_ACT_S = DDR_CRRD - 1;

  localparam DELAY_ACT_TO_R_W = 1 << (CYCLES_ACT_TO_R_W - 2);
  localparam DELAY__RD_TO__RD = 1 << (CYCLES__RD_TO__RD - 2);
  localparam DELAY__RD_TO__WR = 1 << (CYCLES__RD_TO__WR - 2);
  localparam DELAY__WR_TO__RD = 1 << (CYCLES__WR_TO__RD - 2);
  localparam DELAY__WR_TO__WR = 1 << (CYCLES__WR_TO__WR - 2);

  // todo: fix/finalise these timings ...
  localparam DELAY_RDA_TO_ACT = 1 << (CYCLES_RDA_TO_ACT - 1);
  // localparam DELAY_WRA_TO_ACT = 1 << (CYCLES_WRA_TO_ACT - 1);
  localparam DELAY_WRA_TO_ACT = 1 << (CYCLES_WRA_TO_ACT + 1);  // todo


  reg [WSB:0] wr_delay, rd_delay;
  reg wr_strob, wr_ready, rd_ready;
  reg run_q, ready, busy;
  reg [XSB:0] count;
  reg [DSB:0] delay;

  wire precharge, nop_w;
  wire [XSB:0] cnext;


  // -- Connect to Upstream Controller & Data-paths -- //

  assign ctl_run_o = run_q;
  assign ctl_rdy_o = ready;
  assign precharge = ctl_adr_i[10];

  assign mem_wready_o = WR_PREFETCH ? wr_strob : wr_ready;
  assign mem_rvalid_o = dfi_rvld_i;
  assign mem_rlast_o = dfi_last_i;
  assign mem_rddata_o = dfi_data_i;


  // -- Internal Control Signals -- //

  assign nop_w = ~ctl_req_i | ~ready;
  assign cnext = count - 1;


  // -- Connect to the DDR PHY IOB's -- //

  assign dfi_odt_o = 1'b0;
  assign dfi_wstb_o = wr_strob;
  assign dfi_wren_o = wr_ready;
  assign dfi_mask_o = mem_wrmask_i;
  assign dfi_data_o = mem_wrdata_i;
  assign dfi_rden_o = rd_ready;

  generate
    if (LOW_LATENCY) begin : g_low_latency

      // -- Version for Direct Connection: FSM -> PHY -- //

      assign dfi_ras_no = nop_w ? CMD_NOOP[2] : ctl_cmd_i[2];
      assign dfi_cas_no = nop_w ? CMD_NOOP[1] : ctl_cmd_i[1];
      assign dfi_we_no  = nop_w ? CMD_NOOP[0] : ctl_cmd_i[0];
      assign dfi_addr_o = ctl_adr_i;
      assign dfi_bank_o = ctl_ba_i;

    end else begin : g_med_latency

      // -- Registered-commands Version -- //

      reg [2:0] cmd_q, ba_q;
      reg [RSB:0] adr_q;

      assign dfi_ras_no = cmd_q[2];
      assign dfi_cas_no = cmd_q[1];
      assign dfi_we_no  = cmd_q[0];
      assign dfi_bank_o = ba_q;
      assign dfi_addr_o = adr_q;

      always @(posedge clock) begin
        if (nop_w || !ddr_cke_i) begin
          cmd_q <= CMD_NOOP;
        end else begin
          cmd_q <= ctl_cmd_i;
        end

        ba_q  <= ctl_ba_i;
        adr_q <= ctl_adr_i;
      end

    end
  endgenerate


  // -- Upstream-enable Logic -- //

  // todo: this can be used to bring a SDRAM out of power-down mode ??
  always @(posedge clock) begin
    run_q <= run_q | delay[0] & ~ddr_cke_i;
  end


  // -- Main DDR3 PHY-control State Machine -- //

  // todo:
  //  - read -> read sequencing
  //  - read -> write sequencing
  //  - write -> write sequencing
  //  - write -> read sequencing
  //  - (row) precharge delays
  //  - optimise the FSM-encoding for LUT4-based FPGAs
  //  - can use last command as the state-value ??

  reg [2:0] state;

  always @(posedge clock) begin
    if (reset || !ddr_cke_i) begin
      state <= CMD_NOOP;
      ready <= 1'b0;
      busy  <= 1'b0;
      delay <= DINIT;
      count <= CZERO;
    end else if (busy || !ready) begin
      state <= state;
      if (cnext == CZERO) begin
        ready <= 1'b1;
        busy  <= 1'b0;
      end else begin
        ready <= delay[0];
        busy  <= busy;
      end
      delay <= {1'b0, delay[DSB:1]};
      count <= busy ? cnext : count;
    end else if (ctl_req_i && ready) begin
      // All commands are spaced by at least one NOP, with this implementation
      ready <= 1'b0;

      case (state)
        CMD_NOOP: begin
          state <= ctl_cmd_i;

          case (ctl_cmd_i)
            // Row-ACTIVATE, which precedes RD/WR
            // Default activation time is 6 cycles (DLL=off) ??
            CMD_ACTV: begin
              busy  <= 1'b0;
              delay <= DELAY_ACT_TO_R_W;
              count <= {CBITS{1'bx}};
            end

            // Bank (and row) PRECHARGE
            // Note: usually a PRECHARGE ALL command
            // Default is 2 cycles (DLL=off)
            CMD_PREC: begin
              busy  <= 1'b0;
              delay <= DELAY_PRE_TO_ACT;
              count <= {CBITS{1'bx}};
            end

            // REFRESH the SDRAM contents
            // Defaults to 11 cycles, at 100 MHz (DLL=off)
            CMD_REFR: begin
              busy  <= 1'b0;
              delay <= DELAY_REF_TO_ACT;
              count <= {CBITS{1'bx}};
            end

            // Set MODE register
            CMD_MODE: begin
              busy  <= 1'b0;
              delay <= DELAY_MRD_TO_CMD;
              count <= {CBITS{1'bx}};
            end

            // Impedance calibration
            // Defaults to 512 cycles, with DLL=off
            CMD_ZQCL: begin
              busy  <= 1'b1;
              delay <= 0;
              count <= DDR_CZQINIT;
            end

            // Ignore these, other than noting that the memory-contoller is
            // being a bit weird ...
            CMD_NOOP: begin
              busy  <= 1'b0;
              delay <= 0;
              count <= {CBITS{1'bx}};
            end

            default: begin
              // Invalid command ...
              busy  <= 1'b0;
              count <= {CBITS{1'bx}};
              delay <= 0;
            end
          endcase
        end

        CMD_ACTV: begin
          // ACTIVATE a row/page within a bank
          // Note: the command has been issued in parallel with this clause, so
          //   we are just determing the delay-length, and which state we'll be
          //   in for the next command
          if (precharge && (ctl_cmd_i == CMD_READ || ctl_cmd_i == CMD_WRIT)) begin
            // AUTO-PRECHARGE issued with the command, so back to IDLE ...
            state <= CMD_NOOP;
          end else begin
            // Else, just make the state match the command ...
            state <= ctl_cmd_i;
          end

          // todo: probably would be easy to support more commands ??
          case (ctl_cmd_i)
            CMD_READ: delay <= precharge ? DELAY_RDA_TO_ACT : DELAY__RD_TO__RD;
            CMD_WRIT: delay <= precharge ? DELAY_WRA_TO_ACT : DELAY__WR_TO__WR;
            CMD_ACTV: delay <= DELAY_ACT_TO_ACT_S;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        CMD_READ: begin
          if (precharge && (ctl_cmd_i == CMD_READ || ctl_cmd_i == CMD_WRIT)) begin
            // AUTO-PRECHARGE issued with the command, so back to IDLE ...
            state <= CMD_NOOP;
          end else begin
            // Else, just make the state match the command ...
            state <= ctl_cmd_i;
          end

          // todo: check timings and testbenches
          //  - RD -> RD (default: 4 cycles)
          //  - RD -> WR (default: 6 cycles)
          //  - RD -> ACT (default: 4 cycles)
          case (ctl_cmd_i)
            CMD_READ: delay <= precharge ? DELAY_RDA_TO_ACT : DELAY__RD_TO__RD;
            CMD_WRIT: delay <= precharge ? DELAY_WRA_TO_ACT : DELAY__RD_TO__WR;
            CMD_ACTV: delay <= 2;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        CMD_WRIT: begin
          if (precharge && (ctl_cmd_i == CMD_READ || ctl_cmd_i == CMD_WRIT)) begin
            // AUTO-PRECHARGE issued with the command, so back to IDLE ...
            state <= CMD_NOOP;
          end else begin
            // Else, just make the state match the command ...
            state <= ctl_cmd_i;
          end

          // todo: check timings and testbenches
          //  - WR + AUTO-PRECHARGE (default: 14 cycles)
          //  - WR -> WR (default: 4 cycles)
          //  - WR -> RD (default: 14 + 4 cycles)
          //  - WR -> ACT (default: 4 cycles, different bank)
          //  - WR -> PRE -> ACT (default: 16 cycles, same bank)
          case (ctl_cmd_i)
            CMD_WRIT: delay <= precharge ? DELAY_WRA_TO_ACT : DELAY__WR_TO__WR;
            CMD_READ: delay <= precharge ? DELAY_RDA_TO_ACT : DELAY__WR_TO__RD;
            CMD_ACTV: delay <= 2;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        CMD_PREC: begin  // PRECHARGE
          state <= ctl_cmd_i;

          case (ctl_cmd_i)
            CMD_ACTV: delay <= DELAY_PRE_TO_ACT;
            CMD_REFR: delay <= DELAY_REF_TO_ACT;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        CMD_REFR: begin  // REFRESH
          state <= ctl_cmd_i;

          case (ctl_cmd_i)
            CMD_ACTV: delay <= DELAY_ACT_TO_R_W;
            CMD_REFR: delay <= DELAY_REF_TO_ACT;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        CMD_MODE: begin  // SET MODE REG
          state <= ctl_cmd_i;

          case (ctl_cmd_i)
            CMD_MODE: delay <= DELAY_MRD_TO_CMD;
            CMD_REFR: delay <= DELAY_REF_TO_ACT;
            CMD_PREC: delay <= DELAY_PRE_TO_ACT;
            CMD_ZQCL: delay <= 0;
            default:  delay <= {DELAY{1'bx}};
          endcase

          case (ctl_cmd_i)
            CMD_ZQCL: begin
              busy  <= 1'b1;
              count <= DDR_CZQINIT;
            end
            default: begin
              busy  <= 1'b0;
              count <= {CBITS{1'bx}};
            end
          endcase
        end

        CMD_ZQCL: begin  // CALIBRATE
          state <= ctl_cmd_i;

          case (ctl_cmd_i)
            CMD_ACTV: delay <= DELAY_ACT_TO_R_W;
            CMD_REFR: delay <= DELAY_REF_TO_ACT;
            CMD_PREC: delay <= DELAY_PRE_TO_ACT;
            default:  delay <= {DELAY{1'bx}};
          endcase

          busy  <= 1'b0;
          count <= {CBITS{1'bx}};
        end

        default: begin
          // Unexpected state ...
          state <= CMD_NOOP;
          ready <= 1'b0;
          busy  <= 1'b0;
          delay <= DINIT;
          count <= CZERO;
        end
      endcase
    end else if (ready) begin
      // No follow-up command, so IDLE
      state <= CMD_NOOP;
      ready <= 1'b1;
      busy  <= 1'b0;
      delay <= 0;
      count <= {CBITS{1'bx}};
    end
  end


  // -- READ- and WRITE- Data-Paths -- //

  wire store_w, wr_rdy_w;
  wire fetch_w, rd_rdy_w;

  assign store_w = ctl_cmd_i == CMD_WRIT && ready;
  assign fetch_w = ctl_cmd_i == CMD_READ && ready;

  always @(posedge clock) begin
    if (store_w) begin
      wr_delay <= {WDLYS{1'b1}};
    end else begin
      wr_delay <= {1'b0, wr_delay[WSB:1]};
    end

    if (fetch_w) begin
      rd_delay <= {WDLYS{1'b1}};
    end else begin
      rd_delay <= {1'b0, rd_delay[WSB:1]};
    end

    wr_strob <= wr_rdy_w;  // Enables 'DQS' one cycle earlier
    wr_ready <= wr_strob;

    rd_ready <= rd_rdy_w;
  end

  generate
    if (WR_SHIFTS == RD_SHIFTS) begin : g_one_srl
      // Use just a single, double-wide SRL
      // todo: is this more efficient on non-Xilinx ??

      initial $display("== Using combined W/R-delays SRL");

      shift_register #(
          .WIDTH(2),
          .DEPTH(16)
      ) wr_rd_srl_inst (
          .clock (clock),
          .wren_i(1'b1),
          .addr_i(WR_SHIFTS),
          .data_i({wr_delay[0], rd_delay[0]}),
          .data_o({wr_rdy_w, rd_rdy_w})
      );

    end else begin : g_two_srl

      shift_register #(
          .WIDTH(1),
          .DEPTH(16)
      ) wr_srl_inst (
          .clock (clock),
          .wren_i(1'b1),
          .addr_i(WR_SHIFTS),
          .data_i(wr_delay[0]),
          .data_o(wr_rdy_w)
      );

      shift_register #(
          .WIDTH(1),
          .DEPTH(16)
      ) rd_srl_inst (
          .clock (clock),
          .wren_i(1'b1),
          .addr_i(RD_SHIFTS),
          .data_i(rd_delay[0]),
          .data_o(rd_rdy_w)
      );

    end
  endgenerate


  // -- Simulation Only -- //

`ifdef __icarus
  // Make some noise during simulation ...
  always @(posedge clock) begin
    if (!reset && ddr_cke_i && !busy && ctl_req_i && ready) begin
      case (state)
        CMD_NOOP: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_PREC, CMD_REFR, CMD_MODE, CMD_ZQCL: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_IDLE'", $time, ctl_cmd_i);
            end
            CMD_NOOP: $display("%10t: DDL: Unnecessary NOP request", $time);
            default:  $error("%10t: DDL: Invalid command: 0x%1x", $time, ctl_cmd_i);
          endcase
        end

        CMD_ACTV: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_WRIT, CMD_READ: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_ACTV'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_ACTV'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_READ: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_WRIT, CMD_READ: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_READ'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_READ'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_WRIT: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_WRIT, CMD_READ: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_WRIT'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_WRIT'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_PREC: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_REFR: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_PREC'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_PREC'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_REFR: begin
          case (ctl_cmd_i)
            CMD_ACTV: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_REFR'", $time, ctl_cmd_i);
            end
            CMD_REFR: begin
              $display("%10t: DDL: Back-to-back REFRESH commands issued", $time);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_REFR'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_MODE: begin
          case (ctl_cmd_i)
            CMD_MODE, CMD_REFR, CMD_PREC, CMD_ZQCL: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_MODE'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_MODE'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        CMD_ZQCL: begin
          case (ctl_cmd_i)
            CMD_ACTV, CMD_REFR, CMD_PREC: begin
              $display("%10t: DDL: Next command '0x%1x' from 'ST_ZQCL'", $time, ctl_cmd_i);
            end
            default: begin
              $error("%10t: DDL: Unexpected command (0x%1x) in 'ST_ZQCL'", $time, ctl_cmd_i);
              $fatal;
            end
          endcase
        end

        default: $error("%10t: DDL: Unexpected state: 0x%02x", $time, state);
      endcase
    end
  end

  always @(posedge clock) begin
    if (!reset && ddr_cke_i && !ddr_cs_ni) begin
      if (busy && ready) begin
        $error("%10t: Can not by BUSY && READY at the same time!", $time);
        $fatal;
      end
    end
  end


  // -- Pretty States in GtkWave -- //

  reg [79:0] dbg_state;

  always @* begin
    case (state)
      CMD_NOOP: dbg_state = ddr_cke_i & ~ddr_cs_ni & ~reset ? "IDLE" : "INIT";
      CMD_ACTV: dbg_state = "ACTIVATE";
      CMD_READ: dbg_state = "READ";
      CMD_WRIT: dbg_state = "WRITE";
      CMD_PREC: dbg_state = dfi_addr_o[10] ? "PRE-ALL" : "PRECHARGE";
      CMD_REFR: dbg_state = "REFRESH";
      CMD_ZQCL: dbg_state = "ZQCL";
      CMD_MODE: dbg_state = "MODE REG";
      default:  dbg_state = "UNKNOWN";
    endcase
  end

  reg [39:0] dbg_cmd;

  always @* begin
    case ({
      dfi_ras_no, dfi_cas_no, dfi_we_no
    })
      CMD_MODE: dbg_cmd = "MRS";
      CMD_REFR: dbg_cmd = "REF";
      CMD_PREC: dbg_cmd = dfi_addr_o[10] ? "PREA" : "PRE";
      CMD_ACTV: dbg_cmd = "ACT";
      CMD_WRIT: dbg_cmd = dfi_addr_o[10] ? "WR-A" : "WR";
      CMD_READ: dbg_cmd = dfi_addr_o[10] ? "RD-A" : "RD";
      CMD_ZQCL: dbg_cmd = "ZQCL";
      CMD_NOOP: dbg_cmd = "---";
      default:  dbg_cmd = "XXX";
    endcase
  end

`endif


endmodule  // ddr3_ddl

`timescale 1ns / 100ps
module fake_ulpi_phy (  /*AUTOARG*/
    clock,
    reset,

    ulpi_clock_o,
    ulpi_rst_ni,
    ulpi_dir_o,
    ulpi_nxt_o,
    ulpi_stp_i,
    ulpi_data_io,

    usb_tvalid_i,
    usb_tready_o,
    usb_tlast_i,
    usb_tdata_i,

    usb_tvalid_o,
    usb_tready_i,
    usb_tlast_o,
    usb_tdata_o
);

  input clock;
  input reset;

  output ulpi_clock_o;
  input ulpi_rst_ni;
  output ulpi_dir_o;
  input ulpi_stp_i;
  output ulpi_nxt_o;
  inout [7:0] ulpi_data_io;

  // Encoded USB packets IN (from ULPI)
  input usb_tvalid_i;
  output usb_tready_o;
  input usb_tlast_i;
  input [7:0] usb_tdata_i;

  // Decoded USB packets OUT (to ULPI)
  output usb_tvalid_o;
  input usb_tready_i;
  output usb_tlast_o;
  output [7:0] usb_tdata_o;


  // -- Signals & State -- //

  reg dir_q, nxt_q, rdy_q, reg_q;
  reg [7:0] dat_q;

  reg tvalid;
  reg [7:0] tdata;

  wire pid_vld_w, non_pid_w, reg_pid_w, tx_start_w, rx_start_w;


  // -- Output Signal Assignments -- //

  assign ulpi_clock_o = clock;
  // assign ulpi_clock_o = ~clock;
  assign ulpi_dir_o = dir_q;
  assign ulpi_nxt_o = nxt_q;
  assign ulpi_data_io = dir_q ? dat_q : 'bz;

  assign usb_tready_o = rdy_q;

  assign usb_tvalid_o = tvalid;
  assign usb_tlast_o = ulpi_stp_i;
  assign usb_tdata_o = tdata;


  // -- Internal Signal Assignments -- //

  // Valid USB PID means start of packet Rx
  assign tx_start_w = usb_tvalid_i && !rx_start_w;
  assign rx_start_w = pid_vld_w && usb_tready_i;

  assign pid_vld_w = dir_q == 1'b0 && ulpi_data_io[7:4] == 4'b0100;
  assign non_pid_w = dir_q == 1'b0 && ulpi_data_io[7:4] != 4'b0100 && ulpi_data_io != 8'h00;
  assign reg_pid_w = !dir_q && ulpi_data_io[7];


  // -- Rx Datapath -- //

  always @(posedge clock) begin
    case (state)
      default: begin
        tdata  <= 'bx;
        tvalid <= 1'b0;
      end

      ST_IDLE: begin
        tdata  <= ulpi_data_io;
        tvalid <= rx_start_w && nxt_q;
      end

      ST_RECV: begin
        if (!tvalid) begin
          tdata <= {~ulpi_data_io[3:0], ulpi_data_io[3:0]};
        end else begin
          tdata <= ulpi_data_io;
        end
        tvalid <= nxt_q && !ulpi_stp_i;
      end
    endcase
  end


  // -- ULPI FSM -- //

  localparam [3:0] ST_IDLE = 4'b0000;
  localparam [3:0] ST_SEND = 4'b0001;
  localparam [3:0] ST_RECV = 4'b0010;
  localparam [3:0] ST_STOP = 4'b0100;
  localparam [3:0] ST_WAIT = 4'b1000;

  reg [3:0] state, snext;

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      state <= ST_IDLE;

      dir_q <= 1'b0;
      nxt_q <= 1'b0;
      rdy_q <= 1'b0;
      dat_q <= 'bx;
      reg_q <= 1'b0;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          dir_q <= tx_start_w;  //
          nxt_q <= rx_start_w || non_pid_w;  // Pause after PID is standard
          rdy_q <= tx_start_w;
          dat_q <= 'bz;
          reg_q <= reg_pid_w;

          if (reg_q) begin
            state <= ST_WAIT;
            snext <= ST_IDLE;
          end else
          if (!reg_q && rx_start_w) begin
            // ULPI data is coming in over the wire
            state <= ST_RECV;

            // state <= ST_WAIT;
            // snext <= ST_RECV;
          end else if (tx_start_w) begin
            // We need to push data onto the wire
            state <= ST_SEND;

            // state <= ST_STOP;
            // snext <= ST_SEND;
          end else begin
            state <= ST_IDLE;
            snext <= 'bx;
          end
        end

        ST_WAIT: begin
          state <= snext;
          nxt_q <= 1'b0;
          reg_q <= 1'b0;
        end

        ST_SEND: begin
          state <= ulpi_stp_i ? ST_STOP : usb_tlast_i ? ST_IDLE : state;
          snext <= ST_IDLE;

          dir_q <= usb_tvalid_i && !ulpi_stp_i;
          nxt_q <= usb_tvalid_i && !ulpi_stp_i;
          rdy_q <= usb_tvalid_i && !ulpi_stp_i && !usb_tlast_i;
          dat_q <= usb_tdata_i;
        end

        ST_RECV: begin
          // The PHY receives a 'STOP' command to indicate end
          state <= nxt_q && ulpi_stp_i ? ST_IDLE : state;
          snext <= ST_IDLE;

          dir_q <= 1'b0;
          nxt_q <= !ulpi_stp_i;
          rdy_q <= 1'b0;
          dat_q <= dat_q;
        end

        ST_STOP: begin
          // todo: Dump the remainder of the packet in the FIFO ??
          // state <= ST_IDLE;
          state <= snext;
          snext <= 'bx;

          // dir_q <= 1'b0;
          dir_q <= snext == ST_SEND;
          nxt_q <= 1'b0;
          rdy_q <= 1'b0;  // usb_tvalid_i && !usb_tlast_i;
          dat_q <= usb_tdata_i;
        end
      endcase
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_SEND: dbg_state = "SEND";
      ST_RECV: dbg_state = "RECV";
      ST_STOP: dbg_state = "STOP";
      ST_WAIT: dbg_state = "WAIT";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // fake_ulpi_phy

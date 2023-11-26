`timescale 1ns / 100ps
module fake_ulpi_phy (  /*AUTOARG*/
    // Outputs
    ulpi_clock_o,
    ulpi_dir_o,
    ulpi_nxt_o,
    usb_tready_o,
    usb_tvalid_o,
    usb_tlast_o,
    usb_tdata_o,
    // Inouts
    ulpi_data_io,
    // Inputs
    clock,
    reset,
    ulpi_rst_ni,
    ulpi_stp_i,
    usb_tvalid_i,
    usb_tlast_i,
    usb_tdata_i,
    usb_tready_i
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

  // Encoded USB packets OUT (to ULPI)
  output usb_tvalid_o;
  input usb_tready_i;
  output usb_tlast_o;
  output [7:0] usb_tdata_o;


  // -- Signals & State -- //

  reg dir_q, nxt_q, rdy_q;
  reg [7:0] dat_q;

  reg tvalid, tlast;
  reg [7:0] tdata;

  wire pid_valid_w, non_pid_w, tx_start_w, rx_start_w;


  // -- Output Signal Assignments -- //

  assign ulpi_clock_o = ~clock;
  assign ulpi_dir_o = dir_q;
  assign ulpi_nxt_o = nxt_q;
  assign ulpi_data_io = dir_q ? dat_q : 'bz;

  assign usb_tready_o = rdy_q;

  assign usb_tvalid_o = tvalid;
  assign usb_tlast_o = tlast;  // todo: ulpi_stp_i !?
  assign usb_tdata_o = tdata;


  // -- Internal Signal Assignments -- //

  // Valid USB PID means start of packet Rx
  assign pid_valid_w = dir_q == 1'b0 && ulpi_data_io[3:0] == ~ulpi_data_io[7:4];
  assign tx_start_w = usb_tvalid_i && !rx_start_w;
  assign rx_start_w = pid_valid_w && usb_tready_i;

  assign non_pid_w = dir_q == 1'b0 && ulpi_data_io != 8'h0 && ulpi_data_io[3:0] != ~ulpi_data_io[7:4];


  // -- Rx Datapath -- //

  always @(posedge clock) begin
    case (state)
      default: begin
        tdata  <= 'bx;
        tvalid <= 1'b0;
      end

      ST_IDLE: begin
        tdata  <= ulpi_data_io;
        tvalid <= rx_start_w;
      end

      ST_RECV: begin
        tdata  <= ulpi_data_io;
        tvalid <= nxt_q;
        tlast  <= ulpi_stp_i;  // todo: should be combinational !?
      end
    endcase
  end


  // -- ULPI FSM -- //

  localparam ST_IDLE = 3'b000;
  localparam ST_SEND = 3'b001;
  localparam ST_RECV = 3'b010;
  localparam ST_STOP = 3'b100;

  reg [2:0] state;

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      state <= ST_IDLE;

      dir_q <= 1'b0;
      nxt_q <= 1'b0;
      rdy_q <= 1'b0;
      dat_q <= 'bx;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          dir_q <= tx_start_w;  //
          nxt_q <= rx_start_w || non_pid_w;  // Pause after PID is standard
          rdy_q <= tx_start_w;
          dat_q <= 'bz;  // usb_tdata_i;

          if (rx_start_w) begin
            // ULPI data is coming in over the wire
            state <= ST_RECV;
          end else if (tx_start_w) begin
            // We need to push data onto the wire
            state <= ST_SEND;
          end else begin
            state <= ST_IDLE;
          end
        end

        ST_SEND: begin
          state <= ulpi_stp_i ? ST_STOP : usb_tlast_i ? ST_IDLE : state;

          dir_q <= usb_tvalid_i && !ulpi_stp_i;
          nxt_q <= 1'b0;
          rdy_q <= usb_tvalid_i && !ulpi_stp_i && !usb_tlast_i;
          dat_q <= usb_tdata_i;
        end

        ST_RECV: begin
          // The PHY receives a 'STOP' command to indicate end
          state <= nxt_q && ulpi_stp_i ? ST_IDLE : state;

          dir_q <= 1'b0;
          nxt_q <= 1'b1;  // todo
          rdy_q <= 1'b0;
          dat_q <= dat_q;
        end

        ST_STOP: begin
          // todo: Dump the remainder of the packet in the FIFO ??
          state <= ST_IDLE;
          // state <= usb_tvalid_i && !usb_tlast_i ? state : ST_IDLE;

          dir_q <= 1'b0;
          nxt_q <= 1'b0;
          rdy_q <= 1'b0;  // usb_tvalid_i && !usb_tlast_i;
          dat_q <= usb_tdata_i;
        end
      endcase
    end
  end


endmodule  // fake_ulpi_phy

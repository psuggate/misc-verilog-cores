`timescale 1ns / 100ps
module fake_ulpi_phy (
    input clock,
    input reset,

    output ulpi_clock_o,
    input ulpi_rst_ni,
    output ulpi_dir_o,
    input ulpi_stp_i,
    output ulpi_nxt_o,
    inout [7:0] ulpi_data_io,

    // Encoded USB packets IN (from ULPI)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // Decoded USB packets OUT (to ULPI)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o
);

  // -- Constants -- //

  localparam [3:0] ST_IDLE = 4'b0000;
  localparam [3:0] ST_SEND = 4'b0001;
  localparam [3:0] ST_RECV = 4'b0010;
  localparam [3:0] ST_REGW = 4'b0011;
  localparam [3:0] ST_STOP = 4'b0100;
  localparam [3:0] ST_CHRP = 4'b0101;
  localparam [3:0] ST_XSE0 = 4'b0110;
  localparam [3:0] ST_KJKJ = 4'b0111;
  localparam [3:0] ST_INIT = 4'b1111;
  localparam [3:0] ST_WAIT = 4'b1000;


  // -- Signals & State -- //

  reg [3:0] state, snext;

  reg dir_q, nxt_q, rdy_q;
  reg [7:0] dat_q;

  reg tvalid;
  reg [7:0] tdata;

  wire pid_vld_w, non_pid_w, reg_pid_w, tx_start_w, rx_start_w;
  wire [1:0] line_state_w;
  wire [7:0] rx_cmd_w;


  // -- Output Signal Assignments -- //

  assign ulpi_clock_o = clock;
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

  assign pid_vld_w = dir_q == 1'b0 && ulpi_data_io[7:4] == 4'h4 && ulpi_data_io[3:0] != 4'h0;
  assign non_pid_w = dir_q == 1'b0 && ulpi_data_io[7:4] == 4'h4 && ulpi_data_io[3:0] == 4'h0;
  assign reg_pid_w = !dir_q && ulpi_data_io[7];

  // See pp.16, UTMI+ Low Pin Interface (ULPI) Specification
  assign rx_cmd_w = {2'b01, tx_start_w ? 2'b01 : 2'b00, 2'b11, line_state_w};

  assign line_state_w = state == ST_INIT ? 2'b01 :
                        state == ST_CHRP ? (kj_count[3] ? 2'b10 : 2'b01) : 2'b00;


  // -- Rx Datapath -- //

  always @(posedge clock) begin
    case (state)
      default: begin
        tdata  <= 'bx;
        tvalid <= 1'b0;
      end

      ST_WAIT: begin
        if (nxt_q && !dir_q) begin
          tvalid <= 1'b1;
          tdata  <= {~ulpi_data_io[3:0], ulpi_data_io[3:0]};
        end
      end

      ST_RECV: begin
        if (nxt_q && !ulpi_stp_i) begin
          tvalid <= 1'b1;
          tdata  <= ulpi_data_io;
        end else begin
          tvalid <= 1'b0;
          tdata  <= tdata;
        end
      end
    endcase
  end

  // Fake Flow-Control //
  reg [2:0] rnd_q;

  // Randomly de-asserts 'nxt' to test how the flow-control of the upstream and
  // downstream functional-units behave.
  always @(posedge clock) begin
    // rnd_q <= 3'd0; // Disables random flow-stoppages
    rnd_q <= $urandom;
  end


  // -- Fake Chirping -- //

  reg [3:0] kj_count;
  wire [3:0] kj_cnext = kj_count + 4'd1;

  always @(posedge clock) begin
    if (reset) begin
      kj_count <= 4'd0;
    end else begin
      if (state == ST_CHRP) begin
        kj_count <= kj_cnext;
      end
    end
  end


  // -- ULPI FSM -- //

  localparam CONNECT_TIME = 3;
  reg [3:0] count;
  wire [3:0] cnext = count + 4'd1;

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      count <= 4'd0;
    end else if (count < 4'd15) begin
      count <= cnext;
    end
  end

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      state <= ST_INIT;

      dir_q <= 1'b0;
      nxt_q <= 1'b0;
      rdy_q <= 1'b0;
      dat_q <= 'bx;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          rdy_q <= 1'b0;
          dat_q <= 'bz;

          if (reg_pid_w) begin
            nxt_q <= 1'b1;
            dir_q <= 1'b0;
            state <= ST_REGW;
            snext <= ST_IDLE;
          end else if (non_pid_w) begin
            $display("%10t: Tweet, tweet", $time);
            nxt_q <= 1'b1;
            dir_q <= 1'b0;
            state <= ST_CHRP;
            snext <= ST_IDLE;
          end else if (rx_start_w) begin
            // ULPI data is coming in over the wire
            nxt_q <= 1'b1;
            dir_q <= 1'b0;
            state <= ST_WAIT;
            snext <= ST_RECV;
          end else if (tx_start_w) begin
            // We need to push data onto the wire
            nxt_q <= 1'b1;
            dir_q <= 1'b1;
            state <= ST_WAIT;
            snext <= ST_SEND;
          end else begin
            nxt_q <= 1'b0;
            dir_q <= 1'b0;
            state <= ST_IDLE;
            snext <= 'bx;
          end
        end

        ST_REGW: begin
          if (ulpi_stp_i) begin
            state <= ST_IDLE;
            nxt_q <= 1'b0;
          end else begin
            nxt_q <= 1'b1;
          end
        end

        ST_WAIT: begin
          state <= snext;
          snext <= 'bx;

          nxt_q <= 1'b0;
          rdy_q <= snext == ST_SEND;
          dat_q <= snext == ST_SEND ? rx_cmd_w : dat_q;
        end

        //
        //  High-Speed Negotiation Sequence
        ///
        ST_INIT: begin
          state <= count > CONNECT_TIME && ulpi_data_io == 8'h0 ? ST_XSE0 : state;
          dir_q <= count > CONNECT_TIME && ulpi_data_io == 8'h0;
        end

        ST_XSE0: begin
          // Send 'RX CMD' (line-state) of 'SE0'
          dir_q <= 1'b1;
          state <= ST_CHRP;
        end

        ST_CHRP: begin
          // Wait for the K-chirp
          dir_q <= 1'b0;
          dat_q <= 8'bz;
          nxt_q <= 1'b0;
          rdy_q <= 1'b0;
          state <= ulpi_stp_i ? snext : state;
        end

        ST_KJKJ: begin
          dir_q <= ulpi_stp_i ? 1'b0 : kj_count[1] & kj_count[2];
          dat_q <= kj_count[1] && kj_count[2] && dir_q ? rx_cmd_w : 8'bz;
          nxt_q <= 1'b0;
          rdy_q <= 1'b0;
          state <= ulpi_stp_i ? snext : state;
        end

        //
        //  Normal Operation
        ///
        ST_SEND: begin
          state <= ulpi_stp_i ? ST_STOP : usb_tvalid_i && usb_tlast_i && rdy_q ? ST_IDLE : state;
          snext <= ST_IDLE;

          dir_q <= usb_tvalid_i && !ulpi_stp_i;
          nxt_q <= usb_tvalid_i && !ulpi_stp_i && rdy_q;
          rdy_q <= usb_tvalid_i && !ulpi_stp_i && !(rnd_q == 3'b111) && !(usb_tlast_i && rdy_q);
          dat_q <= !rdy_q ? rx_cmd_w : usb_tdata_i;
        end

        ST_RECV: begin
          // The PHY receives a 'STOP' command to indicate end
          state <= ulpi_stp_i ? ST_IDLE : state;
          snext <= ST_IDLE;

          dir_q <= 1'b0;
          nxt_q <= !ulpi_stp_i && !(rnd_q >= 5);
          rdy_q <= 1'b0;
          dat_q <= dat_q;
        end

        ST_STOP: begin
          // todo: Dump the remainder of the packet in the FIFO ??
          state <= ST_IDLE;

          dir_q <= 1'b0;
          nxt_q <= 1'b0;
          rdy_q <= 1'b0;
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
      ST_REGW: dbg_state = "REGW";
      ST_STOP: dbg_state = "STOP";
      ST_WAIT: dbg_state = "WAIT";
      ST_INIT: dbg_state = "INIT";
      ST_XSE0: dbg_state = "XSE0";
      ST_CHRP: dbg_state = "CHRP";
      ST_KJKJ: dbg_state = "KJKJ";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // fake_ulpi_phy

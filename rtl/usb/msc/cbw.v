`timescale 1ns / 100ps
//
// Parser for USB Bulk-Only Transport (BOT) Command Block Wrapper (CBW) frames.
//
module cbw (
    input clock,
    input reset,

    input  enable_i,
    output error_o,

    // From SCSI controller
    input scsi_busy_i,  // Todo: what do I want?
    input scsi_done_i,

    // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // Decoded CBW (Command Block Wrapper)
    output cbw_vld_o,
    output cbw_dir_o,
    input cbw_ack_i,
    output [31:0] cbw_tag_o,
    output [31:0] cbw_len_o,
    output [3:0] cbw_lun_o,

    // SCSI Command Block (CB, via AXI-S)
    output cb_tvalid_o,
    input cb_tready_i,
    output cb_tlast_o,
    output [7:0] cb_tdata_o
);

  reg vld, err, dir, rdy, enb, byp;
  reg [31:0] len, tag;
  reg [3:0] lun;
  reg [4:0] cnt;
  reg [4:0] state;
  wire skid_ready_w, vld_w;

  localparam [4:0] ST_IDLE = 5'd0, ST_SIG1 = 5'd1, ST_SIG2 = 5'd2, ST_SIG3 = 5'd3;
  localparam [4:0] ST_TAG0 = 5'd4, ST_TAG1 = 5'd5, ST_TAG2 = 5'd6, ST_TAG3 = 5'd7;
  localparam [4:0] ST_LEN0 = 5'd8, ST_LEN1 = 5'd9, ST_LEN2 = 5'd10, ST_LEN3 = 5'd11;
  localparam [4:0] ST_FLAG = 5'd12, ST_DLUN = 5'd13, ST_BLEN = 5'd14, ST_SEND = 5'd15;
  localparam [4:0] ST_WAIT = 5'd16, ST_DATO = 5'd17, ST_DATI = 5'd18, ST_FAIL = 5'd19;

  assign error_o = err;

  assign usb_tready_o = byp ? skid_ready_w : rdy;

  assign cbw_vld_o = vld;
  assign cbw_dir_o = dir;  // 1: Bulk-In (device to host)
  assign cbw_tag_o = tag;
  assign cbw_len_o = len;
  assign cbw_lun_o = lun;

  // Check the CB length, which must be in the range [1, 16].
  assign vld_w = usb_tdata_i[7:5] == 3'd0 && usb_tdata_i[4:0] != 5'd0 && usb_tdata_i[4:0] <= 5'd16;

  always @(posedge clock) begin
    if (reset == 1'b1 || cbw_ack_i == 1'b1) begin
      vld <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: vld <= 1'b0;
        ST_FAIL: vld <= 1'b0;
        ST_BLEN: vld <= usb_tvalid_i && vld_w;
        default:
        if (cbw_ack_i) begin
          vld <= 1'b0;
        end
      endcase
    end
  end

  always @(posedge clock) begin
    if (reset == 1'b1) begin
      state <= ST_IDLE;
      byp   <= 1'b0;
      enb   <= 1'b1;
      err   <= 1'b0;
      rdy   <= 1'b0;
      dir   <= 1'bx;
    end else if (enable_i) begin
      case (state)
        ST_IDLE: begin
          byp <= 1'b0;
          enb <= 1'b1;
          err <= 1'b0;
          rdy <= ~scsi_busy_i;
          if (usb_tvalid_i && rdy && usb_tdata_i == 8'h55) begin
            state <= ST_SIG1;
          end else begin
            state <= ST_IDLE;
          end
        end
        ST_SIG1:
        if (usb_tvalid_i && usb_tdata_i == 8'h53) begin
          state <= ST_SIG2;
        end
        ST_SIG2:
        if (usb_tvalid_i && usb_tdata_i == 8'h42) begin
          state <= ST_SIG3;
        end
        ST_SIG3:
        if (usb_tvalid_i && usb_tdata_i == 8'h43) begin
          state <= ST_TAG0;
        end

        ST_TAG0:
        if (usb_tvalid_i) begin
          tag[7:0] <= usb_tdata_i;
          state <= ST_TAG1;
        end
        ST_TAG1:
        if (usb_tvalid_i) begin
          tag[15:8] <= usb_tdata_i;
          state <= ST_TAG2;
        end
        ST_TAG2:
        if (usb_tvalid_i) begin
          tag[23:16] <= usb_tdata_i;
          state <= ST_TAG3;
        end
        ST_TAG3:
        if (usb_tvalid_i) begin
          tag[31:24] <= usb_tdata_i;
          state <= ST_LEN0;
        end

        ST_LEN0:
        if (usb_tvalid_i) begin
          len[7:0] <= usb_tdata_i;
          state <= ST_LEN1;
        end
        ST_LEN1:
        if (usb_tvalid_i) begin
          len[15:8] <= usb_tdata_i;
          state <= ST_LEN2;
        end
        ST_LEN2:
        if (usb_tvalid_i) begin
          len[23:16] <= usb_tdata_i;
          state <= ST_LEN3;
        end
        ST_LEN3:
        if (usb_tvalid_i) begin
          len[31:24] <= usb_tdata_i;
          state <= ST_FLAG;
        end

        ST_FLAG:
        if (usb_tvalid_i) begin
          dir   <= usb_tdata_i[7];
          state <= usb_tdata_i[6:0] == 7'd0 ? ST_DLUN : ST_FAIL;
        end
        ST_DLUN:
        if (usb_tvalid_i) begin
          lun   <= usb_tdata_i[3:0];
          state <= usb_tdata_i[7:4] == 4'd0 ? ST_BLEN : ST_FAIL;
        end
        ST_BLEN:
        if (usb_tvalid_i) begin
          cnt   <= usb_tdata_i[4:0];
          byp   <= 1'b1;
          enb   <= ~vld_w;
          state <= vld_w ? ST_SEND : ST_FAIL;
        end

        // Send the Command Block to the SCSI controller.
        ST_SEND: begin
          if (usb_tvalid_i && usb_tlast_i) begin
            state <= ST_WAIT;
          end
        end

        // Wait for the SCSI controller to read the CB.
        ST_WAIT: begin
          if (cb_tvalid_o && cb_tready_i && cb_tlast_o) begin
            if (dir == 1'b1) begin
              byp   <= 1'b0;
              rdy   <= 1'b0;
              enb   <= 1'b1;
              state <= ST_DATO;
            end else begin
              enb   <= 1'b0;
              state <= ST_DATI;
            end
          end
        end

        // Wait for the SCSI subsystem to send data (device -> host), and block
        // until this has completed -- command-queuing not supported by BOT.
        ST_DATO:
        if (scsi_done_i) begin
          state <= ST_IDLE;
        end

        // Pass data (host -> device) through the skid-register, until the SCSI
        // transaction has completed.
        ST_DATI:
        if (scsi_done_i) begin
          enb   <= 1'b1;
          byp   <= 1'b0;
          state <= ST_IDLE;
        end

        default: begin
          // Failed, so handle error, and return to idle.
          byp   <= 1'b0;
          err   <= 1'b1;
          enb   <= 1'b1;
          rdy   <= usb_tvalid_i && usb_tlast_i ? 1'b0 : 1'b1;
          state <= usb_tvalid_i ? ST_FAIL : ST_IDLE;
        end

      endcase
    end
  end


  axis_skid #(
      .WIDTH (8),
      .BYPASS(0)
  ) U_SKID0 (
      .clock(clock),
      .reset(enb),

      .s_tvalid(usb_tvalid_i),
      .s_tready(skid_ready_w),
      .s_tlast (usb_tlast_i),
      .s_tdata (usb_tdata_i),

      .m_tvalid(cb_tvalid_o),
      .m_tready(cb_tready_i),
      .m_tlast (cb_tlast_o),
      .m_tdata (cb_tdata_o)
  );


endmodule  /* cbw */

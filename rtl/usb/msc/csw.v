`timescale 1ns / 100ps
//
// Generates Command Status Wrapper (CSW) blocks, in response to CBWs.
//
module csw (
    input clock,
    input reset,

    input enable_i,
    input error_i,

    // From SCSI controller
    input scsi_done_i,
    input scsi_fail_i,

    // Decoded CBW (Command Block Wrapper)
    input cbw_vld_i,
    input cbw_dir_i,
    input [31:0] cbw_tag_i,
    input [31:0] cbw_len_i,
    input [3:0] cbw_lun_i,  // Todo: not required?

    // SCSI data from target device, to (USB) host
    input dat_tvalid_i,
    output dat_tready_o,
    input dat_tlast_i,
    input [7:0] usb_tdata_i,

    // USB status, and READ, packet stream (Bulk-Out pipe, AXI-S)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o
);

  reg vld, lst, enb, byp;
  reg [31:0] res;
  reg [ 7:0] dat;
  reg [ 4:0] state;
  wire skid_valid_w, skid_ready_w, skid_last_w;
  wire [7:0] skid_data_w;

  localparam [3:0] ST_IDLE = 4'd0, ST_SIG1 = 4'd1, ST_SIG2 = 4'd2, ST_SIG3 = 4'd3;
  localparam [3:0] ST_TAG0 = 4'd4, ST_TAG1 = 4'd5, ST_TAG2 = 4'd6, ST_TAG3 = 4'd7;
  localparam [3:0] ST_RES0 = 4'd8, ST_RES1 = 4'd9, ST_RES2 = 4'd10, ST_RES3 = 4'd11;
  localparam [3:0] ST_STAT = 4'd12, ST_SEND = 4'd13, ST_FAIL = 4'd15;

  assign dat_tready_o = byp ? skid_ready_w : 1'b0;

  assign skid_valid_w = byp ? dat_tvalid_i : vld;
  assign skid_last_w  = byp ? dat_tlast_i : lst;
  assign skid_data_w  = byp ? dat_tdata_i : dat;

  wire start_w = cbw_vld_i & (scsi_done_i | scsi_fail_i);

  always @(posedge clock) begin
    case (state)
      ST_IDLE: {lst, vld} <= {1'b0, start_w};
      ST_STAT: {lst, vld} <= 2'b11;
      default: {lst, vld} <= 2'b01;
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      byp   <= 1'b0;
      enb   <= 1'b1;
    end else if (enable_i) begin
      case (state)
        ST_IDLE: begin
          dat <= 8'h55;
        end
        ST_SIG1: begin
          dat <= 8'h53;
        end
        ST_SIG2: begin
          dat <= 8'h42;
        end
        ST_SIG3: begin
          dat <= 8'h53;
        end

        ST_TAG0: begin
          dat <= cbw_tag_i[7:0];
        end
        ST_TAG1: begin
          dat <= cbw_tag_i[15:8];
        end
        ST_TAG2: begin
          dat <= cbw_tag_i[23:16];
        end
        ST_TAG3: begin
          dat <= cbw_tag_i[31:24];
        end

        ST_STAT: begin
          if (error_i) begin
            dat <= 8'h02;  // Phase error
          end else if (scsi_fail_i) begin
            dat <= 8'h01;  // Failed
          end else begin
            dat <= 8'h00;  // Success
          end
        end

        default: $fatal("STUB");
      endcase
    end
  end


  axis_skid #(
      .WIDTH (8),
      .BYPASS(0)
  ) U_SKID0 (
      .clock(clock),
      .reset(enb),

      .s_tvalid(skid_valid_w),
      .s_tready(skid_ready_w),
      .s_tlast (skid_last_w),
      .s_tdata (skid_data_w),

      .m_tvalid(usb_tvalid_o),
      .m_tready(usb_tready_i),
      .m_tlast (usb_tlast_o),
      .m_tdata (usb_tdata_o)
  );


endmodule  /* csw */

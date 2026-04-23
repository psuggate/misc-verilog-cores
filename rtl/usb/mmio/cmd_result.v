`timescale 1ns / 100ps
module cmd_result (
    input clock,

    input selected_i,  // From USB controller
    input ack_recv_i,  // From USB controller
    input timedout_i,  // From USB controller

    input  result_i,
    output issued_o,

    // Decoded command (APB, or AXI)
    input [ 3:0] cmd_tag_i,
    input [15:0] cmd_res_i,

    // Output data stream (via AXI-S, to Bulk-In), and USB data or responses
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output usb_tkeep_o,
    output [7:0] usb_tdata_o
);

  // Todo:
  `define CMD_SUCCESS 4'h0
  `define CMD_FAILURE 4'h1
  `define CMD_INVALID 4'hF

  localparam ST_IDLE = 1, ST_SEND = 2, ST_WAIT = 4;
  reg [2:0] state;

  reg vld_q, lst_q, res_q;
  reg  [7:0] out_q;
  reg  [2:0] idx_q;
  wire [3:0] idx_w;

  assign issued_o = res_q;

  assign usb_tvalid_o = vld_q;
  assign usb_tkeep_o = vld_q;
  assign usb_tlast_o = lst_q;
  assign usb_tdata_o = out_q[7:0];

  assign idx_w = idx_q - 1'b1;

  // Writes the MMIO response, after the data transfer stage(s) have completed.
  always @(posedge clock) begin
    case (state)
      ST_IDLE:
      if (selected_i) begin
        idx_q <= 3'd6;
        vld_q <= 1'd1;
        lst_q <= 1'd0;
        out_q <= "T";
      end else begin
        idx_q <= 3'd0;
        vld_q <= 1'b0;
        lst_q <= 1'bx;
        out_q <= 8'bx;
      end

      ST_SEND:
      if (usb_tready_i) begin
        vld_q <= idx_q > 3'd0;
        lst_q <= idx_q == 3'd1;
        idx_q <= idx_w[2:0];
        case (idx_q)
          7, 4: out_q <= "T";
          6: out_q <= "A";
          5: out_q <= "R";
          3: out_q <= cmd_res_i[7:0];
          2: out_q <= cmd_res_i[15:8];
          1: out_q <= {cmd_tag_i, `CMD_SUCCESS};
          default: out_q <= 8'bx;
        endcase
      end

      default:
      if (timedout_i) begin
        idx_q <= 3'd6;
        vld_q <= 1'd1;
        lst_q <= 1'd0;
        out_q <= "T";
      end
    endcase
  end

  always @(posedge clock) begin
    case (state)
      ST_WAIT: res_q <= ack_recv_i;
      default: res_q <= 1'b0;
    endcase
  end

  /**
   * Compute the "residual" of a transaction, of the value returned by an APB
   * transaction.
   *
   * Todo:
   *  - can be either 16-bit value from APB, or the number of bytes _not_ sent;
   *  - how to handle 0 vs 65536 (as the residual)?
   *  - how to count bytes transferred by other end-point?
   */
  always @(posedge clock) begin
    if (!selected_i) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: state <= result_i ? ST_SEND : state;
        ST_SEND: state <= vld_q && lst_q && usb_tready_i ? ST_WAIT : state;
        ST_WAIT: state <= timedout_i ? ST_SEND : state;
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule  /* cmd_result */

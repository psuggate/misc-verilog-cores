`timescale 1ns / 100ps
module transaction (  /*AUTOARG*/);

  parameter EP1_BULK_IN = 1;
  parameter EP1_BULK_OUT = 1;
  parameter EP1_CONTROL = 0;

  parameter EP2_BULK_IN = 1;
  parameter EP2_BULK_OUT = 0;
  parameter EP2_CONTROL = 1;

  parameter ENDPOINT1 = 1;  // set to '0' to disable
  parameter ENDPOINT2 = 2;  // set to '0' to disable

  parameter HIGH_SPEED = 1;


  input clock;
  input reset;

  input [6:0] usb_addr_i;

  input tok_recv_i;
  input [1:0] tok_type_i;
  input [6:0] tok_addr_i;
  input [3:0] tok_endp_i;

  input hsk_recv_i;
  input [1:0] hsk_type_i;

  output ep0_ce_o;  // Control EP
  output ep1_ce_o;  // Bulk EP #1
  output ep2_ce_o;  // Bulk EP #2


  reg ep0_ce_q, ep1_ce_q, ep2_ce_q;

  assign ep0_ce_o = ep0_ce_q;
  assign ep1_ce_o = ep1_ce_q;
  assign ep2_ce_o = ep2_ce_q;


  always @(posedge clock) begin
    if (reset) begin
      {ep2_ce_q, ep1_ce_q, ep0_ce_q} <= 3'b000;
    end else if (tok_recv_i && tok_addr_i == usb_addr_i) begin
      ep0_ce_q <= tok_type_i == 2'b11 && tok_endp_i == 4'h0;
      ep1_ce_q <= ENDPOINT1 != 0 && tok_endp_i == ENDPOINT1[3:0];
      ep2_ce_q <= ENDPOINT2 != 0 && tok_endp_i == ENDPOINT2[3:0];
    end
  end


  localparam CTL_IDLE = 4'h0;

  reg [3:0] state;
  reg [2:0] ctl_req_type_q;

  // todo: recognise control requests to PIPE0
  // todo: then extract the relevant fields
  always @(posedge clock) begin
    if (reset) begin
      state <= CTL_IDLE;
      ctl_req_type_q <= 3'b000;
    end else begin
      case (state)
        CTL_IDLE: begin
          if (tok_rx_recv && tok_rx_endp == 4'h0 && tok_rx_addr == device_address) begin
            state <= CTL_RECV;
          end
        end

        default: begin
          state <= 'bx;
        end
      endcase
    end
  end


endmodule  // transaction

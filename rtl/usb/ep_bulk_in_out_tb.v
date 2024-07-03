`timescale 1ns / 100ps
/**
 *
 * Todo:
 *  - does not react when halted;
 *  - can send/recv small frames;
 *  - resends last packet on failure;
 *  - chunks then re-assembles large frames;
 *  - generates ZDP/'tlast' in response to 'tlast'/ZDP;
 *  - correct behaviour on 'ACK' and timeout;
 *  - FIFO space and packet sizes are correct;
 */
module ep_bulk_in_out_tb;

  localparam integer MAX_PACKET = 512;
  localparam integer FIFO_DEPTH = 2048;

  reg clock = 1;
  reg reset = 0;

  always #5 clock <= ~clock;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("ep_bulk_in_out_tb.vcd");
    $dumpvars;

    #4000 $finish;
  end


  // -- Simulation Stimulus -- //

  reg set_conf = 0;
  reg clr_conf = 0;
  reg selected = 0;

  initial begin
    #5 reset = 1; #10 reset = 0;
    #10 set_conf = 1; #10 set_conf = 0;
  end


  //
  //  Cores Under New Tests
  ///

  ep_bulk_in
    #( .USB_MAX_PACKET_SIZE(MAX_PACKET),
       .PACKET_FIFO_DEPTH(FIFO_DEPTH)
       )
  U_EP_IN1
    ( .clock(clock),
      .reset(reset),

      .set_conf_i(set_conf),
      .clr_conf_i(clr_conf),
      .selected_i(selected)
      );

  ep_bulk_out
    #( .USB_MAX_PACKET_SIZE(MAX_PACKET),
       .PACKET_FIFO_DEPTH(FIFO_DEPTH)
       )
  U_EP_OUT1
    ( .clock(clock),
      .reset(reset),

      .set_conf_i(set_conf),
      .clr_conf_i(clr_conf),
      .selected_i(selected)
      );


endmodule  /* ep_bulk_in_out_tb */

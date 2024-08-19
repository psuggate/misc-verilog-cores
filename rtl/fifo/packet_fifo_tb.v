`timescale 1ns / 100ps
module packet_fifo_tb;

  localparam integer OUTREG = 0;  // Xilinx distributed (LUT) SRAMs
  localparam integer WIDTH = 8;  // byte-width data
  localparam integer ABITS = 7;  // 128 entries
  localparam integer DEPTH = 1 << ABITS;

  localparam integer MSB = WIDTH - 1;
  localparam integer ASB = ABITS - 1;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("packet_fifo_tb.vcd");
    $dumpvars;

    #8000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg clock = 1'b1;
  reg reset = 1'b0;

  always #5.0 clock <= ~clock;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Tasks -- //

  reg drop, save, redo, next;
  wire [ASB:0] level_w;

  reg w_vld, w_lst, r_rdy;
  wire w_rdy, r_vld, r_lst;
  reg  [MSB:0] w_dat;
  wire [MSB:0] r_dat;

  initial begin
    $packet_tb(clock, reset, level_w, drop, save, redo, next, w_vld, w_rdy, w_lst, w_dat, r_vld,
               r_rdy, r_lst, r_dat);
  end


  //
  //  DDR Core Under New Test
  ///

  packet_fifo #(
      .USE_LENGTH(1),
      .MAX_LENGTH(32),
      .SAVE_ON_LAST(0),
      .NEXT_ON_LAST(0),
      .OUTREG(OUTREG),
      .WIDTH(WIDTH),
      .DEPTH(DEPTH)
  ) U_PFIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(level_w),
      .drop_i (drop),
      .save_i (save),
      .redo_i (redo),
      .next_i (next),

      .valid_i(w_vld),
      .ready_o(w_rdy),
      .last_i (w_lst),
      .data_i (w_dat),

      .valid_o(r_vld),
      .ready_i(r_rdy),
      .last_o (r_lst),
      .data_o (r_dat)
  );


endmodule  // packet_fifo_tb

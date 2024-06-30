`timescale 1ns / 100ps
module prefetch_buffer_tb;

  reg clock = 1;
  reg reset = 0;

  always #5 clock <= ~clock;


  initial begin
    #400 $finish;
  end


endmodule  /* prefetch_buffer_tb */

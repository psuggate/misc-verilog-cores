`timescale 1ns / 100ps
module packet_fifo_tb;

  localparam integer OUTREG = 0; // Xilinx distributed (LUT) SRAMs
  localparam integer WIDTH  = 8; // byte-width data
  localparam integer ABITS  = 6; // 64 entries
  localparam integer DEPTH  = 1 << ABITS;

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


  reg w_vld, w_lst, r_rdy;
  wire w_rdy, r_vld, r_lst;
  reg [MSB:0] w_dat;
  wire [MSB:0] r_dat;

  initial begin
    w_vld <= 1'b0;
    w_lst <= 1'b0;
    r_rdy <= 1'b0;
  end


  // -- Simulation Tasks -- //

  task store_packet;
    input [3:0] len;
    begin
      integer count;
      count <= len - 1;

      while (!w_rdy) begin
        @(posedge clock);
      end

      w_vld <= 1'b1;
      w_lst <= !(len > 4'd1);
      r_rdy <= 1'b0;
      w_dat <= $urandom;
      @(posedge clock);

      while (count > 0) begin
        @(posedge clock);
        if (w_rdy) begin
          w_vld <= count > 0;
          w_lst <= !(count > 1);
          w_dat <= w_lst ? w_dat : $urandom;
          count <= count - 1;
        end
      end

      w_vld <= 1'b0;
      w_lst <= 1'b0;
      @(posedge clock);
      $display("%10t: STORE (%3d bytes) complete", $time, len);
    end
  endtask

  task fetch_packet;
    begin
      integer count;

      count <= 0;
      w_vld <= 1'b0;
      w_lst <= 1'b0;
      r_rdy <= 1'b1;
      @(posedge clock);

      while (!r_vld) begin
        @(posedge clock);
      end

      while (r_vld && !r_lst) begin
        count <= count + 1;
        @(posedge clock);
      end

      r_rdy <= 1'b0;
      @(posedge clock);
      $display("%10t: FETCH (%3d bytes) complete", $time, count);
    end
  endtask


  // -- Stimulus -- //

  initial begin
    #50 store_packet(4);
    #10 fetch_packet();
  end


  //
  //  DDR Core Under New Test
  ///
  wire [ASB:0] level_w;

packet_fifo
 #(
   .USE_LENGTH(1),
   .MAX_LENGTH(4),
   .OUTREG(OUTREG),
   .WIDTH(WIDTH),
   .DEPTH(DEPTH)
 ) U_PFIFO1 (
    .clock(clock),
    .reset(reset),

    .level_o(level_w),
    .drop_i(1'b0),
    .save_i(1'b0),
    .redo_i(1'b0),
    .next_i(1'b0),

    .valid_i(w_vld),
    .ready_o(w_rdy),
    .last_i(w_lst),
    .data_i(w_dat),

    .valid_o(r_vld),
    .ready_i(r_rdy),
    .last_o(r_lst),
    .data_o(r_dat)
);


endmodule  // packet_fifo_tb

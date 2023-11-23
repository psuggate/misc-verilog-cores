`timescale 1ns / 100ps
module sync_fifo_tb;

  localparam WIDTH = 2;
  localparam MSB = WIDTH - 1;
  localparam ABITS = 4;
  localparam ASB = ABITS - 1;
  localparam LIMIT = 10;

  reg clock = 1'b1;
  reg reset = 1'b0;

  always #5 clock <= ~clock;


  reg wr_valid, rd_ready;
  wire wr_ready, rd_valid, rd_last;
  reg [MSB:0] wr_data;
  wire [MSB:0] rd_data, rd_xfer, wr_xfer;

  reg start = 1'b0;
  reg frame = 1'b0;
  reg done = 1'b0;
  integer count = 0;

  initial begin
    $dumpfile("sync_fifo_tb.vcd");
    $dumpvars;
    #15 reset <= 1'b1;
    #20 reset <= 1'b0;

    #20 start <= 1'b1;
    #10 start <= 1'b0;

    #10 while (!done) #10;

    #20 $finish;
  end

  initial #4000 $finish;


  // -- Generate Fake Data -- //

  integer rx = 0;

  localparam TEST_MODE = 1;
  localparam OUTREG = 3;

  reg  xx_ready;
  wire ww_ready = (xx_ready || TEST_MODE < 3) && rd_ready && !done;

  assign wr_xfer = wr_ready && wr_valid ? wr_data : 8'bz;
  assign rd_xfer = ww_ready && rd_valid ? rd_data : 8'bz;

  always @(posedge clock) begin
    if (reset) begin
      count <= 0;
      frame <= 1'b0;
      done <= 1'b0;
      wr_valid <= 1'b0;
      rd_ready <= 1'b0;
      xx_ready <= 1'b0;
      rx <= 0;
    end else begin
      if (start) begin
        frame <= 1'b1;
        rd_ready <= TEST_MODE != 1;
      end

      xx_ready <= ~xx_ready;

      if (frame) begin
        // Delay the RX of data ...
        if (TEST_MODE == 1) begin
          rd_ready <= count > 4;
        end

        if (!wr_valid && wr_ready) begin
          wr_valid <= count < LIMIT;
          wr_data  <= $urandom;
        end else if (wr_valid && wr_ready) begin
          if (TEST_MODE < 2) begin
            wr_valid <= 1'b0;
            wr_data  <= 'hx;
          end else begin
            wr_valid <= count < LIMIT - wr_ready;
            wr_data  <= $urandom;
          end

          if (count < LIMIT) begin
            count <= count + 1;
          end
        end

        frame <= count < LIMIT;
      end else begin
        wr_valid <= 1'b0;
        wr_data  <= 'hx;
      end

      if (rd_valid && ww_ready && rx < LIMIT) begin
        rx <= rx + 1;
      end

      done <= rx >= LIMIT;

    end
  end


  // -- Module Under New Test -- //

  wire [ASB:0] sy_level;
  wire [MSB:0] dato = wr_valid & wr_ready ? wr_data : 'bz;
  wire [MSB:0] datz = rd_valid & ww_ready ? rd_data : 'bz;

  sync_fifo #(
      .WIDTH (WIDTH),
      .ABITS (ABITS),
      .OUTREG(OUTREG)
  ) sync_fifo_inst (
      .clock(clock),
      .reset(reset),

      .level_o(sy_level),

      .valid_i(wr_valid),
      .ready_o(wr_ready),
      .data_i (wr_data),

      .valid_o(rd_valid),
      .ready_i(ww_ready),
      .data_o (rd_data)
  );


  // -- Core Under New Test -- //

  wire pw_valid, pw_ready, pw_last, pw_drop, pr_valid, pr_last;
  wire [MSB:0] pr_data;

  assign pw_valid = wr_valid & pw_ready;
  assign pw_last  = 1'b1;
  assign pw_drop  = 1'b0;

  packet_fifo #(
      .WIDTH (WIDTH),
      .ABITS (ABITS),
      .OUTREG(OUTREG)
  ) packet_fifo_inst (
      .clock(clock),
      .reset(reset),

      .valid_i(pw_valid),
      .ready_o(pw_ready),
      .last_i (pw_last),
      .drop_i (pw_drop),
      .data_i (wr_data),

      .valid_o(pr_valid),
      .last_o (pr_last),
      .ready_i(ww_ready),
      .data_o (pr_data)
  );


  //
  //  Simulation Tasks
  ///

  // -- Run a Test -- //
/*
  task run_test;
    input [1:0] mode;
    input [31:0] limit;
    begin
      integer tx, rx;

      done <= 1'b0;
      tx <= 0;
      rx <= 0;
      wr_valid <= 0;
      rd_ready <= 0;

      @(posedge clock);
      start <= 1'b1;

      while (!done) begin
        @(posedge clock);

        xx_ready <= ~xx_ready;

        if (start) begin
          frame <= 1'b1;
          start <= 1'b0;
          rd_ready <= mode != 1;
        end

        if (frame) begin

          if (mode == 1) begin
            rd_ready <= tx > 4;
          end

          if (!wr_valid && wr_ready) begin
            wr_valid <= tx < limit;
            wr_data  <= $urandom;
          end else if (wr_valid && wr_ready) begin
            if (mode < 2) begin
              wr_valid <= 1'b0;
              wr_data  <= 'hx;
            end else begin
              wr_valid <= tx < limit - wr_ready;
              wr_data  <= $urandom;
            end

            if (tx < limit) begin
              tx <= tx + 1;
            end
          end

          frame <= tx < limit;

        end else begin
          wr_valid <= 1'b0;
          wr_data  <= 'hx;
        end

        if (rd_valid && ww_ready && rx < limit) begin
          rx <= rx + 1;
        end

        done <= rx >= limit;

      end

      @(posedge clock);
    end
  endtask  // run_test
*/


endmodule  // sync_fifo_tb

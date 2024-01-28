`timescale 1ns / 100ps
module axis_chop_tb;

  localparam integer ITERATIONS = 1;

  localparam MAXLEN = 64;
  localparam MBITS = $clog2(MAXLEN + 1);
  localparam MSB = MBITS - 1;
  localparam MZERO = {MBITS{1'b0}};


  // -- Simulation Data -- //

  initial begin
    $dumpfile("axis_chop_tb.vcd");
    $dumpvars;

    #5000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg clock = 1'b1, reset;

  always #5 clock <= ~clock;

  initial begin
    reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

  reg mvalid, mlast;
  reg [7:0] mdata;
  wire svalid, sready, slast, mready;
  wire [7:0] sdata;

  // todo ...
  reg act_q, rdy_q;
  reg [MSB:0] len_q;
  wire fin_w;

  initial begin
    #10 @(posedge clock);
    while (reset) begin
      act_q  <= 1'b0;
      len_q  <= 11;
      mvalid <= 1'b0;
      mlast  <= 1'b0;
      @(posedge clock);
    end
    @(posedge clock);

    send_data(8);
    @(posedge clock);

    send_data(16);
    @(posedge clock);

    act_q <= 1'b1;
    @(posedge clock);
    send_data(4);
    @(posedge clock);

    act_q <= 1'b1;
    @(posedge clock);
    send_data(4);
    @(posedge clock);

    #50 $finish;
  end

  always @(posedge clock) begin
    if (reset) begin
      rdy_q <= 1'b0;
    end else begin
      rdy_q <= $urandom;
    end
  end


  //
  //  Core Under New Tests
  ///
  assign sready = act_q && rdy_q;

  axis_chop #(
      .WIDTH (8),
      .MAXLEN(MAXLEN),
      .BYPASS(0)
  ) axis_skid_inst (
      .clock(clock),
      .reset(reset),

      .active_i(act_q),
      .length_i(len_q),
      .final_o (fin_w),

      .s_tvalid(mvalid),
      .s_tready(mready),
      .s_tlast (mlast),
      .s_tdata (mdata),

      .m_tvalid(svalid),
      .m_tready(sready),
      .m_tlast (slast),
      .m_tdata (sdata)
  );


  // -- Simulation Tasks -- //

  task send_data;
    input [MSB:0] len;
    begin
      integer count;
      reg done;

      act_q  <= 1'b1;
      done   <= 1'b0;
      count  <= len;
      mvalid <= 1'b1;
      mlast  <= 1'b0;
      mdata  <= $urandom;
      @(posedge clock);

      while (!done) begin
        @(posedge clock);
        if (count != 0 && mvalid && mready) begin
          mvalid <= count > 1;
          mlast  <= count < 3 && !mlast;
          mdata  <= !fin_w && count > 1 ? $urandom : mdata;
          count  <= count - 1;
        end else begin
          mlast  <= mlast && count != 0;
        end
        done <= svalid && sready && slast;
      end

      act_q  <= 1'b0;
      mvalid <= 1'b0;
      @(posedge clock);
      $display("%10t: DATA SEND (%d bytes)", $time, len);
    end
  endtask


endmodule // axis_chop_tb

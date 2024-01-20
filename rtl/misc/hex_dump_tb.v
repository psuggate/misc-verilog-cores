`timescale 1ns / 100ps
module hex_dump_tb;

  // -- Simulation Data -- //

  localparam BYTES_PER_LINE = 8;
  localparam SIMULATION_LEN = 8000;

  initial begin
    $display("Hex-Dump Testbench");
    $dumpfile("hex_dump_tb.vcd");
    $dumpvars;
  end


  // -- Globals -- //

  reg clock = 1'b1, reset;

  always #5 clock <= ~clock;

  initial begin
    reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Testbench Stimulus -- //

  reg tstart, tvalid;
  reg [2:0] tcount;
  reg [7:0] tdata;
  wire tcycle, tready, tlast, tkeep;

  wire xvalid, xready, xlast;
  wire [7:0] xdata;

  assign tlast  = tcount == 3'd7;
  assign tkeep  = tvalid;
  assign xready = 1'b1;

  always @(posedge clock) begin
    if (reset) begin
      tcount <= 3'd0;
    end else begin
      if (!tcycle) begin
        tstart <= 1'b1;
        tvalid <= 1'b1;
        tcount <= 3'd0;
        tdata  <= $urandom;
      end else if (tvalid && tready) begin
        tcount <= tcount + 3'd1;
        tdata  <= $urandom;
        if (tlast) begin
          tvalid <= 1'b0;
        end
      end
    end
  end


  //
  // Cores Under New Tests
  ///
  hex_dump #(
      .UNICODE(1),
      .BLOCK_SRAM(1),
      .DODGY_FIFO(1)
  ) U_HEXDUMP1 (
      .clock(clock),
      .reset(reset),

      .start_dump_i(tstart),
      .is_dumping_o(tcycle),
      .fifo_level_o(),

      .s_tvalid(tvalid),
      .s_tready(tready),
      .s_tlast (tlast),
      .s_tkeep (tkeep),
      .s_tdata (tdata),

      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tlast (xlast),
      .m_tkeep (),
      .m_tdata (xdata)
  );


  // -- Simulation Output & Termination -- //

  reg xdone;

  initial begin
    xdone <= 1'b0;
    #(SIMULATION_LEN)
    while (!xdone) begin
      if (xvalid && xready && xdata == "\n") begin
        $write("%s", xdata);
        xdone <= 1;
      end
      @(posedge clock);
    end
    $finish;
  end

  always @(posedge clock) begin
    if (reset) begin
    end else begin
      if (xvalid && xready && xdata != 8'd0) $write("%s", xdata);
    end
  end


endmodule // hex_dump_tb

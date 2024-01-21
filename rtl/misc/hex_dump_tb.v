`timescale 1ns / 100ps
module hex_dump_tb;

  //
  //  Simulation Settings
  ///
  localparam UNICODE_OUTPUT = 0;
  localparam BYTES_PER_LINE = 8;
  localparam SIMULATION_LEN = 4000;
  localparam RANDOM_READIES = 1;
  localparam USE_BLOCK_SRAM = 0; // 1;
  localparam USE_DODGY_FIFO = 1; // 0;


  // -- Simulation Data -- //

  initial begin
    $display("Hex-Dump Testbench");
    $dumpfile("hex_dump_tb.vcd");
    $dumpvars;
    #(SIMULATION_LEN + SIMULATION_LEN / 2) $finish;
  end


  // -- Globals -- //

  reg clock = 1'b1, reset;

  always #5 clock <= ~clock;

  initial begin
    reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Testbench Stimulus -- //

  localparam CBITS = $clog2(BYTES_PER_LINE);
  localparam CZERO = {CBITS{1'b0}};
  localparam CSB = CBITS - 1;

  reg tstart, tvalid;
  reg [CSB:0] tcount;
  reg [7:0] tdata;
  wire tcycle, tready, tlast, tkeep;
  wire [10:0] tlevel;

  reg xready, xdone;
  wire xvalid, xlast;
  wire [7:0] xdata;

  assign tlast  = tcount == {CBITS{1'b1}};
  assign tkeep  = tvalid;

  always @(posedge clock) begin
    if (reset) begin
      tstart <= 1'b0;
      tvalid <= 1'b0;
      tcount <= CZERO;
    end else begin
      if (!tcycle && !tstart) begin
        tstart <= 1'b1;
        tvalid <= 1'b1;
        tcount <= CZERO;
        tdata  <= $urandom;
      end else if (tvalid && tready) begin
        tstart <= 1'b0;
        tcount <= tcount + {{CSB{1'b0}}, 1'b1};
        tdata  <= tlast ? tdata : $urandom;
        if (tlast) begin
          tvalid <= 1'b0;
        end
      end
    end
  end


  // -- Simulation Output & Termination -- //

  wire t_err, x_err;

  initial begin
    while (!t_err && !x_err) begin
      @(posedge clock);
    end
    @(posedge clock);
    $display("%10t: Terminating due to AXIS flow-control error (T: %d, X: %d)", $time, t_err, x_err);
    $finish;
  end

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
      xready <= 1'b0;
    end else begin
      if (RANDOM_READIES) begin
        xready <= $urandom;
      end else begin
        xready <= 1'b1;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
    end else begin
      if (xvalid && xready && xdata != 8'd0 && !xdone) $write("%s", xdata);
    end
  end


  // Monitor for AXIS flow-control rules violations
  axis_flow_check U_AXIS_FLOW1 (
      .clock(clock),
      .reset(reset),
      .error(t_err),
      .axis_tvalid(tvalid),
      .axis_tready(tready),
      .axis_tlast(tlast),
      .axis_tdata(tdata)
  );

  axis_flow_check U_AXIS_FLOW2 (
      .clock(clock),
      .reset(reset),
      .error(x_err),
      .axis_tvalid(xvalid),
      .axis_tready(xready),
      .axis_tlast(xlast),
      .axis_tdata(xdata)
  );


  //
  // Cores Under New Tests
  ///
  hex_dump #(
      .UNICODE(UNICODE_OUTPUT),
      .BLOCK_SRAM(USE_BLOCK_SRAM),
      .DODGY_FIFO(USE_DODGY_FIFO)
  ) U_HEXDUMP1 (
      .clock(clock),
      .reset(reset),

      .start_dump_i(tstart),
      .is_dumping_o(tcycle),
      .fifo_level_o(tlevel),

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


endmodule // hex_dump_tb

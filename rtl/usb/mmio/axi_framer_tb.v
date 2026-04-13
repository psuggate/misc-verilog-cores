`timescale 1ns / 100ps
module axi_framer_tb;

  reg clk = 1, rst = 0;
  reg vld, dir;
  reg [15:0] len;
  reg [3:0] lun;
  reg [27:0] adr;
  wire rdy;

  reg axi_ready_q, axi_finish_q;
  wire axi_valid_w, axi_write_w;
  wire [ 7:0] axi_length_w;
  wire [ 3:0] axi_strobe_w;
  wire [31:0] axi_address_w;

  wire [8:0] fifo_wr_level_w, fifo_rd_level_w;

  always #5 clk <= ~clk;

  initial begin : FRAMER_INIT
    $dumpfile("axi_framer_tb.vcd");
    $dumpvars;
    #8000 $finish;
  end  // FRAMER_INIT

  /**
   * Simulation stimulus.
   */
  reg store = 0, slast = 0;
  reg fetch = 0, flast = 0;
  reg [7:0] sdata, fdata;
  integer ii;

  initial begin : AXI_CMD
    // Bring to known state:
    #10 rst = 1;
    vld = 0;
    axi_ready_q = 0;
    axi_finish_q = 0;
    #20 rst = 0;

    // Send 'cmd' to DUT:
    #20 vld = 1;
    dir = 1;
    len = 6;
    lun = 0;
    adr = 63;
    $display("%10t: AXI write issued (n = %d)", $time, len);

    // Fill write-data FIFO:
    for (ii = 0; ii < len; ii = ii + 1) begin
      #10 store = 1;
      slast = 0;
      sdata = $random;
    end
    #10 store = 1;
    slast = 1;
    sdata = $random;
    #10 store = 0;
    slast = 0;
    $display("%10t: AXI data sent (n = %d)", $time, len);

    #10 while (!rdy) #10;
    vld = 0;
    $display("%10t: AXI transaction complete", $time);
  end  // AXI_CMD

  /**
   * Support modules for the simulation.
   */
  wire wr_valid_w, wr_ready_w, wr_last_w;
  wire rd_valid_w, rd_ready_w, rd_last_w;
  wire [7:0] wr_data_w, rd_data_w;

  localparam KZERO = 1'b0;

  assign wr_ready_w = 1'b0;
  assign rd_ready_w = 1'b0;

  axis_sfifo #(
      .WIDTH (8),
      .DEPTH (512),
      .OUTREG(3),
      .TKEEP (0),
      .TLAST (1),
      .USELIB(0)
  ) U_WRFIFO1 (
      .clock  (clk),
      .reset  (rst),
      .level_o(fifo_wr_level_w),

      .s_tvalid(store),
      .s_tready(),
      .s_tkeep (KZERO),
      .s_tlast (slast),
      .s_tdata (sdata),

      .m_tvalid(wr_valid_w),
      .m_tready(wr_ready_w),
      .m_tkeep (),
      .m_tlast (wr_last_w),
      .m_tdata (wr_data_w)
  );

  axis_sfifo #(
      .WIDTH (8),
      .DEPTH (512),
      .OUTREG(3),
      .TKEEP (0),
      .TLAST (1),
      .USELIB(0)
  ) U_RDFIFO1 (
      .clock  (clk),
      .reset  (rst),
      .level_o(fifo_rd_level_w),

      .s_tvalid(fetch),
      .s_tready(),
      .s_tkeep (KZERO),
      .s_tlast (flast),
      .s_tdata (fdata),

      .m_tvalid(rd_valid_w),
      .m_tready(rd_ready_w),
      .m_tkeep (),
      .m_tlast (rd_last_w),
      .m_tdata (rd_data_w)
  );

  /* ====================================================================== */

  /**
   * Component Under Neuromorphological Testing.
   */
  axi_framer AF1 (
      .cmd_clk  (clk),
      .cmd_rst  (rst),
      .cmd_vld_i(vld),
      .cmd_dir_i(dir),
      .cmd_rdy_o(rdy),
      .cmd_len_i(len),
      .cmd_lun_i(lun),
      .cmd_adr_i(adr),

      .fifo_rd_level_i(fifo_rd_level_w),
      .fifo_wr_level_i(fifo_wr_level_w),

      .axi_vld_o(axi_valid_w),
      .axi_dir_o(axi_write_w),
      .axi_ack_i(axi_ready_q),
      .axi_fin_i(axi_finish_q),
      .axi_len_o(axi_length_w),
      .axi_stb_o(axi_strobe_w),
      .axi_adr_o(axi_address_w)
  );

  /* ====================================================================== */

endmodule  /* axi_framer_tb */

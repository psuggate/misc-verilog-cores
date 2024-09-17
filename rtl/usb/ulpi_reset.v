`timescale 1ns / 100ps
module ulpi_reset #(
    parameter [31:0] PHASE = "1000",
    parameter PLLEN = 0
) (
    input areset_n,
    input ulpi_clk,
    input sys_clock,

    output ulpi_rst_n,  // Active LO
    output pll_locked,

    output usb_clock,  // 60 MHz, PLL output, phase-shifted
    output usb_reset,  // Active HI
    output ddr_clock   // 120 MHz, PLL output, phase-shifted
);

  // todo: good enough ??
  localparam NEGATE_CLOCK = PHASE[31:24] == "1";

  reg [4:0] reset_count = 5'd0;
  reg [2:0] reset_delay = 3'd7;
  wire locked, clockd, clockp;

  initial begin
    $display("ULPI Reset module:");
    $display(" - Clock-negation: %1d", NEGATE_CLOCK);
  end


  assign ulpi_rst_n = reset_count[4];
  assign usb_reset  = reset_delay[2];

  assign pll_locked = PLLEN ? locked : ulpi_rst_n;
  assign usb_clock  = PLLEN ? clockd : NEGATE_CLOCK ? ~ulpi_clk : ulpi_clk;
  assign ddr_clock  = PLLEN ? clockp : 1'b0;


  // Reset delays after ULPI clock starts
  always @(posedge sys_clock or negedge areset_n) begin
    if (!areset_n) begin
      reset_count <= 5'd0;
    end else begin
      if (!reset_count[4]) begin
        reset_count <= reset_count + 5'd1;
      end
    end
  end

  // Reset delays after the PLL clock starts
  always @(posedge usb_clock or negedge pll_locked) begin
    if (!pll_locked) begin
      reset_delay <= 3'b111;
    end else begin
      reset_delay <= {reset_delay[1:0], ~reset_count[4]};
    end
  end


  generate
    if (PLLEN) begin : g_gowin_pll

      // PLL for the 60.0 MHz ULPI clock, to derive the 120 MHz DDR clock
      // fixme: does not enter HIGH-SPEED mode, presumably because the start-up
      //   sequence is wrong, due to the extra 'locked' time !?
      // fixme: needs new start-up sequencing, and then to figure out the correct
      //   phase-shift !?
      gw2a_rpll #(
          .FCLKIN("60"),
          .CLKOUTD_SRC("CLKOUTP"),
          .PSDA_SEL(PHASE),
          .IDIV_SEL(3),  // div 4
          .FBDIV_SEL(7),  // mul 8
          .ODIV_SEL(8),  // div 8
          .DYN_SDIV_SEL(2)  // div 2
      ) U_RPLL0 (
          .clockp(clockp),    // 120 MHz
          .clockd(clockd),    // 60 MHz
          .lock  (locked),
          .clkin (ulpi_clk),
          .reset (1'b0)
      );

    end
  endgenerate


endmodule  // ulpi_reset

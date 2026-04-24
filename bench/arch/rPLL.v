module rPLL (
    CLKOUT,
    CLKOUTP,
    CLKOUTD,
    CLKOUTD3,
    LOCK,
    CLKIN,
    CLKFB,
    FBDSEL,
    IDSEL,
    ODSEL,
    DUTYDA,
    PSDA,
    FDLY,
    RESET,
    RESET_P
);
  input CLKIN;
  input CLKFB;
  input RESET;
  input RESET_P;
  input [5:0] FBDSEL;
  input [5:0] IDSEL;
  input [5:0] ODSEL;
  input [3:0] PSDA, FDLY;
  input [3:0] DUTYDA;

  output CLKOUT;
  output LOCK;
  output CLKOUTP;
  output CLKOUTD;
  output CLKOUTD3;

  parameter FCLKIN = "100.0";  // frequency of the CLKIN(M)
  parameter DYN_IDIV_SEL = "false";  //true:IDSEL; false:IDIV_SEL
  parameter IDIV_SEL = 0;  // 0:1,1:2...63:64. 1~64
  parameter DYN_FBDIV_SEL = "false";  //true:FBDSEL; false:FBDIV_SEL
  parameter FBDIV_SEL = 0;  // 0:1,1:2...63:64. 1~64
  parameter DYN_ODIV_SEL = "false";  //true:ODSEL; false:ODIV_SEL
  parameter ODIV_SEL = 8;  // 2/4/8/16/32/48/64/80/96/112/128

  parameter PSDA_SEL = "0000";  //
  parameter DYN_DA_EN = "false";  //true:PSDA or DUTYDA or FDA; false: DA_SEL
  parameter DUTYDA_SEL = "1000";  //

  parameter CLKOUT_FT_DIR = 1'b1;  // CLKOUT fine tuning direction. 1'b1 only
  parameter CLKOUTP_FT_DIR = 1'b1;  // 1'b1 only
  parameter CLKOUT_DLY_STEP = 0;  // 0,1,2,4
  parameter CLKOUTP_DLY_STEP = 0;  // 0,1,2

  parameter CLKFB_SEL = "internal";  //"internal", "external";
  parameter CLKOUT_BYPASS = "false";  //"true"; "false"
  parameter CLKOUTP_BYPASS = "false";  //"true"; "false"
  parameter CLKOUTD_BYPASS = "false";  //"true"; "false"
  parameter DYN_SDIV_SEL = 2;  // 2~128,only even num
  parameter CLKOUTD_SRC = "CLKOUT";  //CLKOUT,CLKOUTP
  parameter CLKOUTD3_SRC = "CLKOUT";  //CLKOUT,CLKOUTP
  parameter DEVICE = "GW2A-55";//"GW2A-18","GW2A-55","GW2AR-18","GW2A-55C","GW2A-18C","GW2AR-18C","GW2ANR-18C","GW2AN-55C"

  wire resetn;
  wire [5:0] IDIV_SEL_reg, FBDIV_SEL_reg;
  wire [5:0] IDIV_dyn, FBDIV_dyn;
  reg [5:0] IDIV_SEL_reg1, FBDIV_SEL_reg1, ODSEL_reg;
  wire div_dyn_change;
  integer IDIV_reg, FBDIV_reg;
  wire clk_div_src;
  reg clk_effect, oclk_effect, oclk_build;
  realtime curtime, pretime, fb_delay;
  realtime clkin_cycle[4:0];
  realtime clkin_period, clkin_period1, clkout_period, tclkout_half, tclkout_half_new;
  realtime clkfb_curtime, clkin_curtime, FB_dly, FB_dly0;
  reg clkin_init, fb_clk_init;
  reg clkout, clk_out, clkfb_reg, clkoutp, clk_ps_reg, clk_ps_reg0;
  reg clkfb;
  reg lock_reg;
  realtime ps_dly, f_dly, clkout_duty, ps_value, duty_value, tclkp_duty;
  real unit_div = 1.0, real_fbdiv = 1.0;
  integer cnt_div;
  reg clkout_div_reg;
  integer multi_clkin;
  wire div3_in;
  integer cnt_div3;
  reg div3_reg;
  reg clkfb_init, div3_init, pre_div3_in;

  initial begin
    IDIV_reg = 1;
    FBDIV_reg = 1;
    clkin_cycle[0] = 0;
    clkin_cycle[1] = 0;
    clkin_cycle[2] = 0;
    clkin_cycle[3] = 0;
    clkin_cycle[4] = 0;
    clkin_period = 0;
    clkin_period1 = 0;
    clkout_period = 0;
    clk_effect = 1'b0;
    oclk_effect = 1'b0;
    oclk_build = 1'b0;
    clkfb_reg = 1'b0;
    clkout = 1'b0;
    clk_out = 1'b0;
    clkfb = 1'b0;
    clkoutp = 1'b0;
    clkin_init = 1'b1;
    fb_clk_init = 1'b1;
    clkfb_init = 1'b1;
    FB_dly = 0.0;
    FB_dly0 = 0.0;
    clkin_curtime = 0.0;
    clkfb_curtime = 0.0;
    lock_reg = 0;
    clk_ps_reg = 0;
    clk_ps_reg0 = 0;
    clkout_div_reg = 0;
    cnt_div = 0;
    div3_init = 1'b1;
    cnt_div3 = 0;
    div3_reg = 0;
    f_dly = 0.0;
    ps_dly = 0.0;
  end

  assign resetn = ~(RESET | RESET_P);

  // determine period of CLKIN and clkout
  always @(posedge CLKIN or negedge resetn) begin
    if (!resetn) begin
      clk_effect <= 1'b0;
      clkin_cycle[0] <= 0;
    end else begin
      pretime <= curtime;
      curtime <= $realtime;

      if (pretime > 0) begin
        clkin_cycle[0] <= curtime - pretime;
      end

      if (clkin_cycle[0] > 0) begin
        clkin_cycle[1] <= clkin_cycle[0];
        clkin_cycle[2] <= clkin_cycle[1];
        clkin_cycle[3] <= clkin_cycle[2];
        clkin_cycle[4] <= clkin_cycle[3];
      end

      if (clkin_cycle[0] > 0) begin
        if(((clkin_cycle[0] - clkin_period1 < 0.01) && (clkin_cycle[0] - clkin_period1 > -0.01)) &&(!div_dyn_change)) begin
          clk_effect   <= 1'b1;
          clkin_period <= clkin_period1;
        end else begin
          clk_effect <= 1'b0;
        end
      end
    end
  end

  always @(clkin_cycle[0] or clkin_cycle[1] or clkin_cycle[2] or clkin_cycle[3] or clkin_cycle[4]  or clkin_period1) begin
    if (clkin_cycle[0] != clkin_period1) begin
      clkin_period1 <= (clkin_cycle[0]+clkin_cycle[1]+clkin_cycle[2]+clkin_cycle[3]+clkin_cycle[4])/5;
    end
  end

  // IDSEL/FBDSEL    IDIV_dyn/FBDIV_dyn
  // 111111	divider   /1
  // 111110	divider   /2
  // .	.
  // .	.
  // .	.
  // 000000	divider   /64
  assign IDIV_dyn = 64 - IDSEL;
  assign FBDIV_dyn = 64 - FBDSEL;

  assign IDIV_SEL_reg = (DYN_IDIV_SEL == "true") ? IDIV_dyn : (IDIV_SEL + 1);
  assign FBDIV_SEL_reg = (DYN_FBDIV_SEL == "true") ? FBDIV_dyn : (FBDIV_SEL + 1);

  always @(posedge CLKIN) begin
    IDIV_SEL_reg1 <= IDIV_SEL_reg;
    FBDIV_SEL_reg1 <= FBDIV_SEL_reg;
    ODSEL_reg <= ODSEL;
  end

  assign div_dyn_change = (IDIV_SEL_reg1 != IDIV_SEL_reg) || (FBDIV_SEL_reg1 != FBDIV_SEL_reg) || (ODSEL_reg != ODSEL);

  always @(clkin_period or IDIV_SEL_reg or FBDIV_SEL_reg) begin
    real_fbdiv = (FBDIV_SEL_reg * unit_div);
    clkout_period = ((clkin_period * IDIV_SEL_reg) / real_fbdiv);
    tclkout_half = (clkout_period / 2);
  end

  realtime clk_tlock_cur;
  realtime max_tlock;
  integer  cnt_lock;
  initial begin
    clk_tlock_cur = 0.0;
    max_tlock = 0.0;
    cnt_lock = 0;
  end

  // lock time
  always @(posedge CLKIN or negedge resetn) begin
    if (resetn == 1'b0) begin
      max_tlock <= 0.0;
    end else begin
      if ((clkin_cycle[0] >= 2) && (clkin_cycle[0] <= 40)) begin
        max_tlock <= 50000;
      end else if ((clkin_cycle[0] > 40) && (clkin_cycle[0] <= 500)) begin
        max_tlock <= 200000;
      end
    end
  end

  always @(posedge CLKIN or negedge resetn) begin
    if (resetn == 1'b0) begin
      lock_reg <= 1'b0;
      oclk_effect <= 1'b0;
    end else begin
      if (clk_effect == 1'b1) begin
        cnt_lock <= cnt_lock + 1;

        if (cnt_lock > ((max_tlock / clkin_period) - 10)) begin
          oclk_effect <= 1'b1;
        end else begin
          oclk_effect <= 1'b0;
        end

        if (cnt_lock > (max_tlock / clkin_period)) begin
          lock_reg <= 1'b1;
        end else begin
          lock_reg <= 1'b0;
        end
      end else begin
        oclk_effect <= 1'b0;
        cnt_lock <= 0;
        lock_reg <= 1'b0;
      end
    end
  end

  // calculate CLKFB feedback delay
  always @(posedge CLKIN) begin
    if (clkin_init == 1'b1) begin
      clkin_curtime = $realtime;
      clkin_init = 1'b0;
    end
  end

  always @(posedge CLKFB) begin
    if (fb_clk_init == 1'b1) begin
      clkfb_curtime = $realtime;
      fb_clk_init   = 1'b0;
    end
  end

  always @(CLKFB or CLKIN) begin
    if ((clkfb_curtime > 0) && (clkin_curtime > 0)) begin
      FB_dly0 = clkfb_curtime - clkin_curtime;
      if ((FB_dly0 >= 0) && (clkin_cycle[0] > 0)) begin
        multi_clkin = FB_dly0 / (clkin_cycle[0]);
        FB_dly = clkin_cycle[0] - (FB_dly0 - (clkin_cycle[0]) * multi_clkin);
      end
    end
  end

  // clkout
  always @(clkfb_reg or oclk_effect) begin
    if (oclk_effect == 1'b0) begin
      clkfb_reg = 1'b0;
    end else begin
      if (clkfb_init == 1'b1) begin
        clkfb_reg <= 1'b1;
        clkfb_init = 1'b0;
      end else begin
        clkfb_reg <= #tclkout_half ~clkfb_reg;
      end
    end
  end

  always @(clkfb_reg) begin
    if (CLKFB_SEL == "internal") begin
      clkfb <= clkfb_reg;
    end else begin
      clkfb <= #(FB_dly) clkfb_reg;
    end
  end

  always @(posedge clkfb) begin
    clkout <= 1'b1;
    #tclkout_half_new clkout <= 1'b0;
  end

  always @(CLKIN or oclk_effect or clkout or resetn) begin
    if (resetn == 1'b0) begin
      clk_out <= 1'b0;
    end  //else if (oclk_effect == 1'b1) begin
    else begin
      clk_out <= clkout;
    end
  end

  assign CLKOUT = (CLKOUT_BYPASS == "true") ? CLKIN : clk_out;
  assign LOCK   = lock_reg;

  //clkout_p
  // DYN_DA_EN == "false".
  // phase_shift_value
  always @(*) begin
    case (PSDA_SEL)
      "0000": ps_value = (clkout_period * 0) / 16;
      "0001": ps_value = (clkout_period * 1) / 16;
      "0010": ps_value = (clkout_period * 2) / 16;
      "0011": ps_value = (clkout_period * 3) / 16;
      "0100": ps_value = (clkout_period * 4) / 16;
      "0101": ps_value = (clkout_period * 5) / 16;
      "0110": ps_value = (clkout_period * 6) / 16;
      "0111": ps_value = (clkout_period * 7) / 16;
      "1000": ps_value = (clkout_period * 8) / 16;
      "1001": ps_value = (clkout_period * 9) / 16;
      "1010": ps_value = (clkout_period * 10) / 16;
      "1011": ps_value = (clkout_period * 11) / 16;
      "1100": ps_value = (clkout_period * 12) / 16;
      "1101": ps_value = (clkout_period * 13) / 16;
      "1110": ps_value = (clkout_period * 14) / 16;
      "1111": ps_value = (clkout_period * 15) / 16;
    endcase
  end

  always @(*) begin
    case (DUTYDA_SEL)
      "0000": duty_value = (clkout_period * 0) / 16;
      "0001": duty_value = (clkout_period * 1) / 16;
      "0010": duty_value = (clkout_period * 2) / 16;
      "0011": duty_value = (clkout_period * 3) / 16;
      "0100": duty_value = (clkout_period * 4) / 16;
      "0101": duty_value = (clkout_period * 5) / 16;
      "0110": duty_value = (clkout_period * 6) / 16;
      "0111": duty_value = (clkout_period * 7) / 16;
      "1000": duty_value = (clkout_period * 8) / 16;
      "1001": duty_value = (clkout_period * 9) / 16;
      "1010": duty_value = (clkout_period * 10) / 16;
      "1011": duty_value = (clkout_period * 11) / 16;
      "1100": duty_value = (clkout_period * 12) / 16;
      "1101": duty_value = (clkout_period * 13) / 16;
      "1110": duty_value = (clkout_period * 14) / 16;
      "1111": duty_value = (clkout_period * 15) / 16;
    endcase
  end

  // DYN_DA_EN == "true".
  always @(FDLY) begin
    if (DYN_DA_EN == "true") begin
      if (DEVICE == "GW1N-1" || DEVICE == "GW1N-1S") begin
        case (FDLY)
          4'b0000: f_dly = 0.000;
          4'b0001: f_dly = 0.125;
          4'b0010: f_dly = 0.250;
          4'b0100: f_dly = 0.500;
          4'b1000: f_dly = 1.000;
          default: f_dly = 0.000;
        endcase
      end else begin
        case (FDLY)
          4'b1111: f_dly = 0.000;
          4'b1110: f_dly = 0.125;
          4'b1101: f_dly = 0.250;
          4'b1011: f_dly = 0.500;
          4'b0111: f_dly = 1.000;
          default: f_dly = 0.000;
        endcase
      end
    end
  end

  always @(PSDA or DUTYDA or ps_value or duty_value) begin
    if (DYN_DA_EN == "true") begin
      ps_dly = (clkout_period * PSDA) / 16;
      if (DUTYDA > PSDA) begin
        clkout_duty = (clkout_period * (DUTYDA - PSDA)) / 16;
      end else if (DUTYDA < PSDA) begin
        clkout_duty = (clkout_period * (16 + DUTYDA - PSDA)) / 16;
      end else begin
        clkout_duty = (clkout_period) / 2;
      end
    end else begin
      ps_dly = ps_value;
      clkout_duty = duty_value;
    end
  end

  always @(tclkout_half or clkout_duty) begin
    if (DYN_DA_EN == "false") begin
      tclkout_half_new <= tclkout_half;
      tclkp_duty <= clkout_duty;
    end else begin
      if (CLKOUT_FT_DIR == 1'b1) begin
        tclkout_half_new <= tclkout_half - (0.05 * CLKOUT_DLY_STEP);
      end else begin
        tclkout_half_new <= tclkout_half + (0.05 * CLKOUT_DLY_STEP);
      end

      if (CLKOUTP_FT_DIR == 1'b1) begin
        tclkp_duty <= clkout_duty - (0.05 * CLKOUTP_DLY_STEP);
      end else begin
        tclkp_duty <= clkout_duty + (0.05 * CLKOUTP_DLY_STEP);
      end
    end
  end

  always @(posedge clkfb) begin
    clkoutp <= 1'b1;
    #tclkp_duty clkoutp <= 1'b0;
  end

  always @(clkoutp) begin
    clk_ps_reg0 <= #(ps_dly + f_dly) clkoutp;
  end

  always @(CLKIN or oclk_effect or clk_ps_reg0 or resetn) begin
    if (resetn == 1'b0) begin
      clk_ps_reg <= 1'b0;
    end  //else if (oclk_effect == 1'b1) begin
    else begin
      clk_ps_reg <= clk_ps_reg0;
    end
  end

  assign CLKOUTP = (CLKOUTP_BYPASS == "true") ? CLKIN : clk_ps_reg;

  //divide
  assign clk_div_src = (CLKOUTD_SRC == "CLKOUTP") ? clk_ps_reg0 : clkout;

  always @(posedge clk_div_src or negedge resetn) begin
    if (!resetn) begin
      cnt_div <= 0;
      clkout_div_reg <= 0;
    end else begin
      cnt_div = cnt_div + 1;
      if (cnt_div == DYN_SDIV_SEL / 2) begin
        clkout_div_reg <= ~clkout_div_reg;
        cnt_div <= 0;
      end
    end
  end

  assign CLKOUTD = (CLKOUTD_BYPASS == "true") ? CLKIN : clkout_div_reg;

  // div3
  assign div3_in = (CLKOUTD3_SRC == "CLKOUTP") ? clk_ps_reg : clk_out;

  always @(div3_in) begin
    pre_div3_in <= div3_in;
  end

  always @(div3_in or negedge resetn) begin
    if (div3_init == 1'b1) begin
      if (pre_div3_in == 1'b1 && div3_in == 1'b0) begin
        div3_reg <= 1;
        div3_init = 1'b0;
        cnt_div3  = 0;
      end
    end else if (resetn == 1'b0) begin
      div3_reg <= 0;
      cnt_div3 = 0;
    end else begin
      cnt_div3 = cnt_div3 + 1;
      if (cnt_div3 == 3) begin
        div3_reg <= ~div3_reg;
        cnt_div3 = 0;
      end
    end
  end

  assign CLKOUTD3 = div3_reg;

endmodule  /* rPLL */

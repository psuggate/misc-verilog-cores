`timescale 1ns / 100ps
module GSR (input GSRI);

  reg GSRO = 1'b0;

  initial begin : BOOT
    #5 GSRO <= 1'b1;
  end

endmodule  // GSR

module TBUF (
    O,
    I,
    OEN
);

  input I, OEN;
  output O;

  bufif0 TB (O, I, OEN);

endmodule  // TBUF (output buffer with tri-state control)

module TLVDS_IOBUF (
    O,
    IO,
    IOB,
    I,
    OEN
);
  output O;
  inout IO, IOB;
  input I, OEN;
  reg O;
  bufif0 IB (IO, I, OEN);
  notif0 YB (IOB, I, OEN);
  always @(IO or IOB) begin
    if (IO == 1'b1 && IOB == 1'b0) O <= IO;
    else if (IO == 1'b0 && IOB == 1'b1) O <= IO;
    else if (IO == 1'bx || IOB == 1'bx) O <= 1'bx;
  end
endmodule

module IDDR (
    Q0,
    Q1,
    D,
    CLK
);

  input D;
  input CLK;
  output Q0;
  output Q1;

  parameter Q0_INIT = 1'b0;
  parameter Q1_INIT = 1'b0;

  wire gsrt = GSR.GSRO;

  reg Q0_oreg, Q1_oreg, Q0_reg, Q1_reg;

  initial begin
    Q0_reg  = Q0_INIT;
    Q1_reg  = Q1_INIT;
    Q0_oreg = Q0_INIT;
    Q1_oreg = Q1_INIT;
  end

  assign Q0 = Q0_reg;
  assign Q1 = Q1_reg;

  always @(gsrt) begin
    if (!gsrt) begin
      assign Q0_reg = Q0_INIT;
      assign Q1_reg = Q1_INIT;
      assign Q0_oreg = Q0_INIT;
      assign Q1_oreg = Q1_INIT;
    end else begin
      deassign Q0_reg;
      deassign Q1_reg;
      deassign Q0_oreg;
      deassign Q1_oreg;
    end
  end

  always @(posedge CLK) begin
    Q0_oreg <= D;
    Q0_reg  <= Q0_oreg;
    Q1_reg  <= Q1_oreg;

  end

  always @(negedge CLK) begin
    Q1_oreg <= D;
  end

endmodule  //IDDR (ddr input)

module ODDR (
    Q0,
    Q1,
    D0,
    D1,
    TX,
    CLK
);

  parameter TXCLK_POL = 1'b0;  //1'b0:Rising edge output; 1'b1:Falling edge output
  parameter INIT = 1'b0;

  input D0;
  input D1;
  input TX;
  input CLK;
  output Q0;
  output Q1;

  reg Dd0_0, Dd0_1, Dd0_2;
  reg Dd1_0, Dd1_1, Dd1_2;
  reg Ttx0, Ttx1, DT0, DT1;
  wire gsrt = GSR.GSRO;

  initial begin
    Dd0_0 = 1'b0;
    Dd0_1 = 1'b0;
    Dd0_2 = 1'b0;
    Dd1_0 = 1'b0;
    Dd1_1 = 1'b0;
    Dd1_2 = 1'b0;
    Ttx0  = 1'b0;
    Ttx1  = 1'b0;
    DT0   = 1'b0;
    DT1   = 1'b0;
  end

  always @(gsrt) begin
    if (!gsrt) begin
      assign Dd1_2 = INIT;
      assign Dd0_2 = INIT;
      assign Dd1_1 = INIT;
      assign Dd0_1 = INIT;
      assign Dd1_0 = INIT;
      assign Dd0_0 = INIT;
      assign Ttx0 = INIT;
      assign Ttx1 = INIT;
      assign DT0 = INIT;
      assign DT1 = INIT;
    end else begin
      deassign Dd1_2;
      deassign Dd0_2;
      deassign Dd1_1;
      deassign Dd0_1;
      deassign Dd1_0;
      deassign Dd0_0;
      deassign Ttx0;
      deassign Ttx1;
      deassign DT0;
      deassign DT1;
    end
  end

  always @(posedge CLK) begin
    Dd0_0 <= D0;
    Dd1_0 <= D1;
    Dd0_1 <= Dd0_0;
    Dd1_1 <= Dd1_0;
    Ttx0  <= TX;
    Ttx1  <= Ttx0;
  end

  always @(posedge CLK) begin
    Dd1_2 <= Dd1_1;
    DT0   <= DT1;
  end

  always @(negedge CLK) begin
    Dd0_2 <= Dd0_1;
    DT1   <= Ttx1;
  end

  assign Q0 = (CLK) ? Dd0_2 : Dd1_2;
  assign Q1 = (TXCLK_POL == 1'b0) ? DT0 : DT1;

endmodule  // ODDR (ddr output)

/**
 * Output serialiser, 4:1 .
 */
module OSER4 (
    Q0,
    Q1,
    D0,
    D1,
    D2,
    D3,
    TX0,
    TX1,
    PCLK,
    FCLK,
    RESET
);

  parameter GSREN = "false";  //"true"; "false"
  parameter LSREN = "true";  //"true"; "false"
  parameter HWL = "false";  //"true"; "false"
  parameter TXCLK_POL = 1'b0;  //1'b0:Rising edge output; 1'b1:Falling edge output

  input D3, D2, D1, D0;
  input TX1, TX0;
  input PCLK, FCLK, RESET;
  output Q0, Q1;

  reg [3:0] Dd1, Dd2, Dd3;
  reg [1:0] Ttx1, Ttx2, Ttx3;
  reg rstn_dsel, dsel, d_up0, d_up1;
  wire d_en0, d_en1;
  reg Qq_n, Q_data_n, Qq_p, Q_data_p;
  wire grstn, lrstn;

  initial begin
    dsel = 1'b0;
  end

  assign grstn = GSREN == "true" ? GSR.GSRO : 1'b1;
  assign lrstn = LSREN == "true" ? (~RESET) : 1'b1;

  always @(posedge PCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Dd1  <= 4'b0;
      Ttx1 <= 2'b0;
    end else if (!lrstn) begin
      Dd1  <= 4'b0;
      Ttx1 <= 2'b0;
    end else begin
      Dd1  <= {D3, D2, D1, D0};
      Ttx1 <= {TX1, TX0};
    end
  end

  always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      rstn_dsel <= 1'b0;
    end else if (!lrstn) begin
      rstn_dsel <= 1'b0;
    end else begin
      rstn_dsel <= 1'b1;
    end
  end

  always @(posedge FCLK or negedge rstn_dsel) begin
    if (!rstn_dsel) begin
      dsel <= 1'b0;
    end else begin
      dsel <= ~dsel;
    end
  end

  assign d_en0 = ~dsel;
  assign d_en1 = (HWL == "true") ? (~dsel) : dsel;

  always @(posedge FCLK or negedge rstn_dsel) begin
    if (!rstn_dsel) begin
      d_up0 <= 1'b0;
      d_up1 <= 1'b0;
    end else begin
      if (d_en0) begin
        d_up0 <= 1'b1;
      end else begin
        d_up0 <= 1'b0;
      end

      if (d_en1) begin
        d_up1 <= 1'b1;
      end else begin
        d_up1 <= 1'b0;
      end
    end
  end

  always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Dd2  <= 4'b0;
      Ttx2 <= 2'b0;
    end else if (!lrstn) begin
      Dd2  <= 4'b0;
      Ttx2 <= 2'b0;
    end else begin
      if (d_up0) begin
        Dd2  <= Dd1;
        Ttx2 <= Ttx1;
      end else begin
        Dd2  <= Dd2;
        Ttx2 <= Ttx2;
      end
    end
  end

  always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Dd3  <= 4'b0;
      Ttx3 <= 2'b0;
    end else if (!lrstn) begin
      Dd3  <= 4'b0;
      Ttx3 <= 2'b0;
    end else begin
      if (d_up1) begin
        Dd3  <= Dd2;
        Ttx3 <= Ttx2;
      end else begin
        Dd3[0]  <= Dd3[2];
        Dd3[2]  <= 1'b0;
        Dd3[1]  <= Dd3[3];
        Dd3[3]  <= 1'b0;
        Ttx3[0] <= Ttx3[1];
        Ttx3[1] <= 1'b0;
      end
    end
  end

  always @(negedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Qq_n <= 1'b0;
      Q_data_n <= 1'b0;
    end else if (!lrstn) begin
      Qq_n <= 1'b0;
      Q_data_n <= 1'b0;
    end else begin
      Qq_n <= Dd3[0];
      Q_data_n <= Ttx3[0];
    end
  end

  always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Qq_p <= 1'b0;
    end else if (!lrstn) begin
      Qq_p <= 1'b0;
    end else begin
      Qq_p <= Dd3[1];
    end
  end

  always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
      Q_data_p <= 1'b0;
    end else if (!lrstn) begin
      Q_data_p <= 1'b0;
    end else begin
      Q_data_p <= Q_data_n;
    end
  end

  assign Q0 = FCLK ? Qq_n : Qq_p;
  assign Q1 = (TXCLK_POL == 1'b0) ? Q_data_p : Q_data_n;


endmodule  // OSER4 (4 to 1 serializer)

module IDES4 (Q0, Q1, Q2, Q3, D, CALIB, PCLK, FCLK, RESET);

parameter GSREN = "false"; //"true"; "false"
parameter LSREN = "true";    //"true"; "false"

input D, FCLK, PCLK, CALIB, RESET;
output Q0,Q1,Q2,Q3;
wire grstn;
wire lrstn; 
//synthesis translate_off

assign grstn = (GSREN == "true") ? GSR.GSRO : 1'b1;
assign lrstn = (LSREN == "true") ? (~RESET) : 1'b1;

reg Dd0,Dd1;
reg [3:0] D_data,data;
reg D_en1,D_en;
reg Dd_sel,calib_state;
reg [3:0] Q_data;
reg reset_delay;
wire CALIBdata_rising_p;
reg [2:0] CALIBdata;
wire dcnt_en;
reg Dd0_reg0,Dd0_reg1,Dd1_reg0,Dd1_reg1;

initial begin
    calib_state = 1'b0;
    D_en1 = 1'b0;
    D_en = 1'b0;
    Dd_sel = 1'b0;
end

always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        Dd0 <= 1'b0;
    end else if (!lrstn) begin
        Dd0 <= 1'b0;
    end else begin
        Dd0 <= D;
    end
end

always @(negedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        Dd1 <= 1'b0;
    end else if (!lrstn) begin
        Dd1 <= 1'b0;
    end else begin
        Dd1 <= D;
    end
end

always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        Dd0_reg0 <= 1'b0;
        Dd0_reg1 <= 1'b0;
        Dd1_reg0 <= 1'b0;
        Dd1_reg1 <= 1'b0;
    end else if (!lrstn) begin
        Dd0_reg0 <= 1'b0;
        Dd0_reg1 <= 1'b0;
        Dd1_reg0 <= 1'b0;
        Dd1_reg1 <= 1'b0;
    end else begin
        Dd0_reg0 <= Dd0;
        Dd0_reg1 <= Dd0_reg0;
        Dd1_reg0 <= Dd1;
        Dd1_reg1 <= Dd1_reg0;
    end
end

always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        reset_delay <= 1'b0;
    end else if (!lrstn) begin
        reset_delay <= 1'b0;
    end else begin
        reset_delay <= 1'b1;
    end
end

always @(posedge FCLK or negedge reset_delay) begin
    if (!reset_delay) begin
        CALIBdata <= 3'b0;
    end else begin
        CALIBdata <= {CALIBdata[1:0], CALIB};
    end
end

assign CALIBdata_rising_p =  CALIBdata[1] && (~CALIBdata[2]);
assign dcnt_en = ~(CALIBdata_rising_p && calib_state);

always @(posedge FCLK or negedge reset_delay) begin
    if (!reset_delay) begin
        calib_state <= 1'b0;
        D_en1 <= 1'b0;
        D_en  <= 1'b0;
        Dd_sel <= 1'b0;
    end else begin
        D_en <= ~D_en1;
        if (CALIBdata_rising_p) begin
            calib_state <= ~calib_state;
            Dd_sel <= ~Dd_sel;
        end else begin
            calib_state <= calib_state;
            Dd_sel <= Dd_sel;
        end
        
        if (dcnt_en) begin
            D_en1 <= ~D_en1;
        end else begin
            D_en1 <= D_en1;
        end
    end
end

always @(Dd_sel or Dd0 or Dd0_reg0 or Dd0_reg1 or Dd1_reg0 or Dd1_reg1) begin
    if(Dd_sel) begin
        D_data[3] = Dd0;
        D_data[2] = Dd1_reg0;
        D_data[1] = Dd0_reg0;
        D_data[0] = Dd1_reg1;
    end else begin
        D_data[3] = Dd1_reg0;
        D_data[2] = Dd0_reg0;
        D_data[1] = Dd1_reg1;
        D_data[0] = Dd0_reg1;
    end
end

always @(posedge FCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        data <= 4'b0;
    end else if (!lrstn) begin
        data <= 4'b0;
    end else if (D_en) begin
        data <= D_data;
    end
end

always @(posedge PCLK or negedge grstn or negedge lrstn) begin
    if (!grstn) begin
        Q_data <= 4'b0;
    end else if (!lrstn) begin
        Q_data <= 4'b0;
    end else begin
        Q_data <= data;
    end
end

assign {Q3,Q2,Q1,Q0} = Q_data;
//synthesis translate_on

endmodule // IDES4 (4 to 1 deserializer)

module IOBUF (O, IO, I, OEN);

input I,OEN;
output O;
inout IO;

buf OB (O, IO);
bufif0 IB (IO,I,OEN);
    
endmodule //IOBUF (inout buffer)

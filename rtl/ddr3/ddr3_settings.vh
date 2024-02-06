/**
 * Default settings for a 1Gb x16 DDR3 SDRAM (assuming the slowest speed-grade,
 * DDR3-800E), and running in DLL=off mode. Therefore, the maximum supported
 * speed (in the JEDEC specifications) is not required to exceed 125 MHz, which
 * corresponds to a data throughput of 500 MB/s (for a x16 device).
 *
 * Copyright 2023, Patrick Suggate.
 */
`ifdef __no_default_settings

// You're probably gonna need something, I reckon ??

`else  /* !__no_default_settings */

//
//  NOTE: Define the parameter 'DDR_FREQ_MHZ' before including this file.
///

localparam TCK = 1000 / DDR_FREQ_MHZ;  // in ns (nanoseconds)

// Low-speed mode, and data-capture "edges" can be a bit trickier
parameter DDR_DLL_OFF = 1;

// Minimum period in DLL=off mode is 8 ns (or, max freq of 125 MHz)
parameter DDR_CL = 6;  // DLL=off mode is required to support this
parameter DDR_CWL = 6;  // DLL=off mode is required to support this

// DDR reset, refresh, and initialisation parameters
parameter DDR_TREFI = 7800;  // REFRESH-interval in ns, at normal temperatures
parameter DDR_TRFC = 160;  // self-REFRESH duration, in ns, for 2Gb DDR3 SDRAM
// parameter DDR_TRFC = 110;  // self-REFRESH duration, in ns, for 1Gb DDR3 SDRAM
localparam DDR_TRESET = 200000;  // RESET# for 200 us after power-on
localparam DDR_TWAKE = 500000;  // after RESET# deasserts, before first command
localparam DDR_TCKE0 = 10;  // at least 10 ns between CKE := 0 and RESET# := 1
localparam DDR_CCKE1 = 5;  // at least 5x cycles between CK valid and CKE := 1
parameter DDR_TXS = 170;  // todo
parameter DDR_TXPR = 170;  // tXPR := max(tXS; 5x tCK)
// parameter DDR_TXPR = $max(DDR_TXS, 5 * TCK);  // tXPR := max(tXS; 5x tCK)
// parameter DDR_TRRD = 10; // tRRD := max(10ns; 4x tCK)

// DDR3-800E (6-6-6) speed bin parameters (from pp. 157)
parameter DDR_TAAMIN = 15;  // min time (ns) for internal-read -> data
parameter DDR_TAAMAX = 20;  // max time (ns) for internal-read -> data
parameter DDR_TWR = 15;  // post-WRITE recovery time, in ns
parameter DDR_TRP = 15;  // min time (ns) for PRE command
parameter DDR_TRCD = 15;  // min time (ns) for ACT -> internal rd/wr
parameter DDR_TRC = 53;  // 52.5;  // min ACT -> {ACT, REF} command period
parameter DDR_TRAS = 38;  // 37.5;  // min ACT -> PRE command period

// From pp. 169
parameter DDR_CDLLK = 512;  // number of cycles for DLL lock
parameter DDR_CZQINIT = 512;  // cycles for ZCQL, or 640 ns (if greater)
parameter DDR_CRTP = 4;  // cycles for internal READ -> PRE
parameter DDR_CWTR = 4;  // cycles for internal WRITE -> internal READ
parameter DDR_CMRD = 4;  // cycles for Mode Reg. Set command
parameter DDR_CMOD = 12;  // cycles for Mode Reg. Set update
parameter DDR_CCCD = 4;  // CAS# -> CAS# command delay (cycles)
parameter DDR_CRRD = 4;  // min ACT -> ACT

// todo: with DLL=off, not relevant because cycle-minimums?
parameter DDR_TRRD = 10;  // in ns, for x16, DDR-800E
parameter DDR_TFAW = 50;  // in ns, for x16, DDR-800E


//
//  Computed Timing Constants
///

// Write-Recovery time, which is the required time for writes to "stick," so
// do not PRECHARGE or READ before this duration has elapsed.
localparam WR_CYCLES = (DDR_TWR + TCK - 1) / TCK;

localparam PRE_CYCLES = (DDR_TRP + TCK - 1) / TCK;

// -- DDR Command Dispatch Delay Constraints -- //

// Wait for at least 5x cycles before issuing first (non-NOP) command
localparam integer CYCLES_CKE_TO_CMD = (DDR_TXPR + TCK - 1) / TCK;  // 5 cycles
localparam integer CYCLES_MRD_TO_CMD = DDR_CMRD + DDR_CMOD;

// Minimum cycles between same bank ACT -> ACT
localparam CYCLES_ACT_TO_ACT = (DDR_TRC + TCK - 1) / TCK;  // both of these must
localparam CYCLES_ACT_TO_PRE = (DDR_TRAS + TCK - 1) / TCK;  // be satisfied

// Minimum cycles between ACT and REF
localparam CYCLES_ACT_TO_REF = CYCLES_ACT_TO_ACT;  // b/c ACT -> PRE -> REF

// Minimum cycles for a self-REF to complete, before ACT (RAS# := 0)
localparam CYCLES_REF_TO_ACT = (DDR_TRFC + TCK - 1) / TCK;

// Minimum of 2 cycles PRE -> ACT (same bank, defaults, DLL=off)
localparam CYCLES_PRE_TO_ACT = (DDR_TRP + TCK - 1) / TCK;

// RAS# -> CAS# is the same as CAS# -> DQ (valid)
localparam CYCLES_ACT_TO_R_W = (DDR_TRCD + TCK - 1) / TCK;
// localparam CYCLES_ACT_TO__RD = DDR_CL;
// localparam CYCLES_ACT_TO__WR = DDR_CWL;

// RD->RD & WR->WR are spaced by at least CAS# -> CAS# delays (of 4 cycles)
localparam CYCLES__RD_TO__RD = DDR_CCCD;  // 4 cycles
localparam CYCLES__WR_TO__WR = DDR_CCCD;  // 4 cycles

// Minimum of 6 cycles RD -> WR (with default settings, DLL=off)
localparam CYCLES__RD_TO__WR = DDR_CL + DDR_CCCD + 2 - DDR_CWL;

// Minimum cycles between issuing WR and RD (same bank)
localparam CYCLES__WR_TO__RD = DDR_CWL + 4 + DDR_CWTR;  // 14 cycles, BL8, DLL=off

// Minimum cycles between issuing WR and PRE (same bank)
localparam CYCLES__WR_TO_PRE = DDR_CWL + 4 + (DDR_TWR + TCK - 1) / TCK;  // 12 cycles

// Minimum cycles between issuing WR with AP, to ACT (same bank)
localparam CYCLES_WRA_TO_ACT = CYCLES__WR_TO_PRE + (DDR_TRP + TCK - 1) / TCK;

// Minimum cycles from RD with AP, to ACT (same bank)
localparam CYCLES_RDA_TO_ACT = DDR_CCCD + (DDR_TRP + TCK - 1) / TCK;  // 6 cycles
// localparam CYCLES_RDA_TO_ACT = DDR_CL + (DDR_TRP + TCK - 1) / TCK; // 8 cycles


//
//  Mode Register Values
///

localparam PPD = 1'b0;  // Slow exit (PRE PD), for DLL=off
// localparam [2:0] WRC = WR_CYCLES == 6 ? 3'b010 : (WR_CYCLES == 5 ? 3'b001 : 3'b000);
localparam [2:0] WRC = 3'b001;
localparam DLLR = 1'b1;  // No DLL reset, for DLL=off
// localparam DLLR = 1'b0;  // No DLL reset, for DLL=off
localparam [3:0] CAS = 4'b0100;  // CL=6 for DLL=off
localparam [1:0] BLEN = 2'b00;  // BL8
localparam [12:0] MR0 = {PPD, WRC, DLLR, 1'b0, CAS[3:1], 1'b0, CAS[0], BLEN};

localparam QOFF = 1'b0;
localparam DLLE = 1'b1;  // DLL=off
localparam [1:0] DIC = 2'b00;  // Driver Impedance Control
localparam [2:0] RTT = 3'b000;  // Nom, nom, nom, ...
localparam [1:0] AL = 2'b00;  // Additive Latency disabled; todo: CL-1 ??
localparam WLE = 1'b0;  // Write Leveling Enable is off
localparam TDQS = 1'b0;  // Only applies to x8 memory
localparam [12:0] MR1 = {
  QOFF, TDQS, 1'b0, RTT[2], 1'b0, WLE, RTT[1], DIC[1], AL, RTT[0], DIC[0], DLLE
};

localparam [1:0] RTTWR = 2'b00;  // Dynamic ODT off
localparam SRT = 1'b0;  // Normal temperature for self-refresh
localparam ASR = 1'b0;  // Manual self-refresh reference
localparam [2:0] CWL = DLLE == 1'b0 ? DDR_CWL - 5 : 3'b001;  // DLL=off, so CWL=6
localparam [2:0] PASR = 3'b000;  // Full Array
localparam [12:0] MR2 = {2'b00, RTTWR, 1'b0, SRT, ASR, CWL, PASR};

localparam [12:0] MR3 = {13'h0000};


//
//  Additional DDR3 Constants
///

// We always have CS# asserted, so: {RAS#, CAS#, WE#}
localparam CMD_NOOP = 3'b111;
localparam CMD_ZQCL = 3'b110;
localparam CMD_READ = 3'b101;
localparam CMD_WRIT = 3'b100;
localparam CMD_ACTV = 3'b011;
localparam CMD_PREC = 3'b010;
localparam CMD_REFR = 3'b001;
localparam CMD_MODE = 3'b000;

`endif

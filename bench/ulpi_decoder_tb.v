`timescale 1ns / 100ps
module ulpi_decoder_tb;

  `include "usb_defs.vh"

  localparam integer USE_IOB_REGS = 1;

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  localparam [6:0] USB_ADDR = 7'd55;
  localparam [3:0] USB_ENDP = 4'd6;

  localparam [3:0] ST_IDLE = 0, ST_XPID = 1, ST_TOKN = 2, ST_TCRC = 3, ST_DATA = 4, ST_CRC0 = 5, ST_CRC1 = 6, ST_EOP0 = 7, ST_EOP1 = 8, ST_HAND = 9, ST_TURN = 14, ST_DONE = 15;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("ulpi_decoder_tb.vcd");
    $dumpvars;

    #2000 $finish;
  end


  // -- Globals -- //

  reg clock = 1'b1, reset;

  always #5 clock <= ~clock;

  initial begin
    reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals -- //

  reg ulpi_dir, ulpi_nxt;
  reg [7:0] ulpi_data;
  reg [1:0] LineState, VbusState, RxEvent;
  reg tready;

  wire crc_error_w, crc_valid_w, dec_idle_w, usb_sof_w;
  wire tok_recv_w, tok_ping_w, hsk_recv_w, usb_recv_w;
  wire [3:0] tok_endp_w, ulpi_rx_tuser_w;
  wire [6:0] tok_addr_w;
  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tkeep_w, ulpi_rx_tlast_w;
  wire [7:0] ulpi_rx_tdata_w;

  reg ksend_q, dsend_q, hsend_q;
  reg [1:0] ttype_q;
  reg [15:0] kdata_q;
  wire tdone_w;

  reg tdone_q;
  reg [63:0] tdata_q;
  wire [7:0] tdata_w;

  reg dir_q, nxt_q;
  reg [7:0] dat_q;
  wire ibuf_dir_w, ibuf_nxt_w;

  reg  [ 3:0] state;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_nw;
  wire [ 1:0] pidty_w;
  wire [7:0] ibuf_dat_w, rxpid_w, rxcmd_w;
  wire ddone_w;

  integer count = 0;

  assign ddone_w = count < 2;

  assign rxcmd_w = {2'b00, RxEvent, VbusState, LineState};
  assign pidty_w = dsend_q ? 2'b11 : ksend_q ? 2'b01 : hsend_q ? 2'b10 : 2'b00;
  assign rxpid_w = {~{ttype_q, pidty_w}, {ttype_q, pidty_w}};
  assign tdone_w = state == ST_TCRC || state == ST_DONE;
  // assign tdata_w = ulpi_nxt ? tdata_q[7:0] : rxcmd_w;
  assign tdata_w = tdata_q[7:0];

  assign ibuf_dir_w = ulpi_dir;
  assign ibuf_nxt_w = ulpi_nxt;
  assign ibuf_dat_w = ulpi_data;

  assign ulpi_rx_tready_w = tready;


  // -- Initialisation -- //

  initial begin : g_init
    tready    <= 1'b0;

    LineState <= 2'd0;
    VbusState <= 2'd3;
    RxEvent   <= 2'd0;

    ksend_q   <= 1'b0;
    dsend_q   <= 1'b0;
    hsend_q   <= 1'b0;
    tdone_q   <= 1'b0;
  end


  // -- Circuit Stimulus -- //

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
    nxt_q <= ulpi_nxt;
    dat_q <= ulpi_data;
  end

  initial begin
    #80 send_token(USB_ADDR, USB_ENDP, TOK_OUT);
    #90 send_data({$urandom, $urandom}, 3'd5, 1'b1);
    #90 handshake(HSK_ACK);
  end


  // -- Tx data CRC Calculation -- //

  genvar ii;
  generate
    for (ii = 0; ii < 16; ii++) begin : g_crc16_revneg
      assign crc16_nw[ii] = ~crc16_q[15-ii];
    end  // g_crc16_revneg
  endgenerate

  always @(posedge clock) begin
    if (state == ST_DATA && stb) begin  // ulpi_nxt) begin
      crc16_q <= crc16(tdata_w, crc16_q);
    end else if (reset || state == ST_IDLE) begin
      crc16_q <= 16'hffff;
    end
  end


  // -- USB Transfer Tasks -- //

  // Encode and send a USB token packet //
  task send_token;
    input [6:0] adr;
    input [3:0] epn;
    input [1:0] typ;
    begin
      {ksend_q, ttype_q, kdata_q} <= {1'b1, typ, {crc5({epn, adr}), epn, adr}};
      @(posedge clock);
      $display("%10t: Sending token: [0x%02x, 0x%02x, 0x%02x]", $time, rxpid_w, kdata_q[7:0],
               kdata_q[15:8]);

      while (ksend_q || !tdone_w) begin
        @(posedge clock);
        if (tdone_w) ksend_q <= 1'b0;
      end
    end
  endtask  // send_token

  // Send either a DATA0 or DATA1 USB packet //
  task send_data;
    input [63:0] data;
    input [2:0] len;
    input odd;
    begin
      {dsend_q, tdone_q, ttype_q, tdata_q} <= {1'b1, 1'b0, odd ? DATA1 : DATA0, data};
      count <= 32'd1 + len;
      @(posedge clock);

      while (count != 0) begin
        if (stb) begin
          count   <= state == ST_DATA ? count - 1 : count;
          tdata_q <= state == ST_DATA ? {8'bx, tdata_q[63:8]} : tdata_q;
          tdone_q <= count < 2;
          dsend_q <= count != 0;
        end
        @(posedge clock);
      end

      dsend_q <= 1'b0;
      tdone_q <= 1'b0;
      @(posedge clock);

      $display("%10t: DATA0 packet sent (bytes: 8)", $time);
    end
  endtask  // send_data

  // Send a USB handshake response
  task handshake;
    input [1:0] typ;
    begin
      {hsend_q, ttype_q} <= {1'b1, typ};
      @(posedge clock);

      while (hsend_q || !hsk_recv_w) begin
        @(posedge clock);
        if (hsk_recv_w) hsend_q <= 1'b0;
      end
    end
  endtask  // handshake


  // -- FSM -- //

  reg stb;

  always @(posedge clock) begin
    stb <= $urandom;
  end

  always @(posedge clock) begin
    if (reset) begin
      state  <= ST_IDLE;
      tready <= 1'b0;
    end else begin
      case (state)
        default: state <= ST_IDLE;
        ST_IDLE: begin
          LineState <= 2'd1;  // todo: Idle 'J' !?
          if (ksend_q || dsend_q || hsend_q) begin
            state     <= ST_TURN;
            RxEvent   <= 2'd1;
            tready    <= 1'b1;
            ulpi_dir  <= 1'b1;
            ulpi_nxt  <= 1'b1;
            ulpi_data <= 'bz;
          end else begin
            state     <= ST_IDLE;
            RxEvent   <= 2'd0;
            tready    <= 1'b0;
            ulpi_dir  <= 1'b0;
            ulpi_nxt  <= 1'b0;
            ulpi_data <= 8'd0;
          end
        end
        ST_TURN: begin
          state <= ST_XPID;
          ulpi_nxt <= 1'b0;
          ulpi_data <= rxcmd_w;
        end
        ST_XPID: begin
          state <= ksend_q ? ST_TOKN : hsend_q ? ST_EOP0 : ST_DATA;
          LineState <= 2'd2;  // todo ...
          ulpi_nxt <= 1'b1;
          ulpi_data <= rxpid_w;
        end

        // USB Token Transfer //
        ST_TOKN: begin
          state <= ST_TCRC;
          ulpi_data <= kdata_q[7:0];
        end
        ST_TCRC: begin
          state <= ST_DONE;
          ulpi_data <= kdata_q[15:8];
        end

        // DATA OUT Transfer //
        ST_DATA: begin
          if (stb) begin
            state <= ddone_w ? ST_CRC0 : state;
            ulpi_nxt <= 1'b1;
            ulpi_data <= tdata_w;
          end else begin
            ulpi_nxt  <= 1'b0;
            ulpi_data <= rxcmd_w;
          end
        end

        ST_CRC0: begin
          if (ulpi_nxt) begin
            state <= ST_CRC1;
            ulpi_data <= crc16_nw[7:0];
          end
          ulpi_nxt <= 1'b1;
        end
        ST_CRC1: begin
          state <= ST_EOP0;
          ulpi_nxt <= 1'b1;
          ulpi_data <= crc16_nw[15:8];
        end
        ST_EOP0: begin
          RxEvent <= 2'd0;
          ulpi_dir <= 1'b1;
          ulpi_nxt <= 1'b0;
          ulpi_data <= rxcmd_w;
          state <= ST_EOP1;
        end
        ST_EOP1: begin
          RxEvent <= 2'd0;
          ulpi_dir <= 1'b1;
          ulpi_nxt <= 1'b0;
          ulpi_data <= rxcmd_w;  // {2'b00, 2'b00, VbusState, LineState};
          state <= ST_DONE;
        end

        ST_HAND: begin
          state <= ST_DONE;
          ulpi_nxt <= 1'b0;
          ulpi_dir <= 1'b1;
          ulpi_data <= rxcmd_w;
        end

        ST_DONE: begin
          LineState <= 2'd0;
          RxEvent   <= 2'd0;
          ulpi_dir  <= 1'b0;
          ulpi_nxt  <= 1'b0;
          ulpi_data <= 8'd0;
          if (ulpi_rx_tvalid_w && ulpi_rx_tready_w && ulpi_rx_tlast_w) begin
            state  <= ST_IDLE;
            tready <= 1'b0;
          end
        end
      endcase
    end
  end


  //
  //  Core Under New Test
  ///
  wire sof_recv_w, eop_recv_w;
  wire uvalid_w, ulast_w, ukeep_w;
  wire [3:0] uuser_w;
  wire [7:0] udata_w;

  wire xdir_w, xnxt_w;
  wire [7:0] xdat_w;

  assign xdir_w = USE_IOB_REGS ? dir_q : ibuf_dir_w;
  assign xnxt_w = USE_IOB_REGS ? nxt_q : ibuf_nxt_w;
  assign xdat_w = USE_IOB_REGS ? dat_q : ibuf_dat_w;

  ulpi_decoder U_DECODER1 (
      .clock(clock),
      .reset(reset),

      .LineState(LineState),

      .ulpi_dir (xdir_w),
      .ulpi_nxt (xnxt_w),
      .ulpi_data(xdat_w),

      .crc_error_o(crc_error_w),
      .crc_valid_o(crc_valid_w),
      .sof_recv_o (sof_recv_w),
      .eop_recv_o (eop_recv_w),
      .dec_idle_o (dec_idle_w),

      .tok_recv_o(tok_recv_w),
      .tok_ping_o(tok_ping_w),
      .tok_addr_o(tok_addr_w),
      .tok_endp_o(tok_endp_w),
      .hsk_recv_o(hsk_recv_w),
      .usb_recv_o(usb_recv_w),

      .m_tvalid(ulpi_rx_tvalid_w),
      .m_tkeep (ulpi_rx_tkeep_w),
      .m_tlast (ulpi_rx_tlast_w),
      .m_tuser (ulpi_rx_tuser_w),
      .m_tdata (ulpi_rx_tdata_w),
      .m_tready(ulpi_rx_tready_w)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [31:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_TURN: dbg_state = "TURN";
      ST_XPID: dbg_state = "XPID";
      ST_TOKN: dbg_state = "TOKN";
      ST_TCRC: dbg_state = "TCRC";
      ST_DATA: dbg_state = "DATA";
      ST_CRC0: dbg_state = "CRC0";
      ST_CRC1: dbg_state = "CRC1";
      ST_EOP0: dbg_state = "EOP0";
      ST_EOP1: dbg_state = "EOP1";
      ST_HAND: dbg_state = "HAND";
      ST_DONE: dbg_state = "DONE";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // ulpi_decoder_tb

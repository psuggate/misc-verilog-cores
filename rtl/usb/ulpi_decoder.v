`timescale 1ns / 100ps
module ulpi_decoder (
    input clock,
    input reset,

    // Raw ULPI IOB inputs
    input ibuf_dir,
    input ibuf_nxt,
    input [7:0] ibuf_data,

    // Registered ULPI IOB inputs
    input ulpi_dir,
    input ulpi_nxt,
    input [7:0] ulpi_data,

    output crc_error_o,
    output crc_valid_o,
    output decode_idle_o,

    input [1:0] LineState,
    input [1:0] VbusState,
    input [1:0] RxEvent,

    output usb_sof_o,

    output tok_recv_o,
    output tok_ping_o,
    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,
    output hsk_recv_o,
    output usb_recv_o,

    output raw_tvalid_o,
    output raw_tlast_o,
    output [7:0] raw_tdata_o,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [3:0] m_tuser,
    output [7:0] m_tdata
);

  `include "usb_crc.vh"

  // -- Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] SPC_PING = 2'b01;

  localparam [1:0] PID_SPECIAL = 2'b00;
  localparam [1:0] PID_TOKEN = 2'b01;
  localparam [1:0] PID_HANDSHAKE = 2'b10;
  localparam [1:0] PID_DATA = 2'b11;

  // USB 'RX_CMD[5:4]' bits
  localparam [1:0] RxActive = 2'b01;
  localparam [1:0] RxError = 2'b11;


  // -- Signals & State -- //

  // Output datapath registers
  reg rx_tvalid, rx_tkeep, rx_tlast;
  reg [3:0] rx_tuser;
  reg [7:0] rx_tdata;

  reg [3:0] endp_q;
  reg [6:0] addr_q;

  // ULPI parser signals
  reg cyc_q, pid_q, dir_q;
  reg [7:0] dat_q;

  // USB packet-type parser signals
  reg hsk_q, tok_q, low_q, sof_q;
  wire pid_vld_w, istoken_w;
  wire [3:0] rx_pid_pw, rx_pid_nw;

  // CRC16 calculation & framing signals
  reg crc_error_flag, crc_valid_flag;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_w;

  // USB packet-receive signals
  reg tok_recv_q, hsk_recv_q, usb_recv_q, sof_recv_q;
  reg  [10:0] token_data;
  wire [ 4:0] rx_crc5_w;


  // -- Output Assignments -- //

  // todo: good enough !?
  assign decode_idle_o = ~cyc_q;

  assign crc_error_o = crc_error_flag;
  assign crc_valid_o = crc_valid_flag;

  assign usb_sof_o = sof_recv_q;
  assign tok_recv_o = tok_recv_q;
  assign tok_ping_o = 1'b0;  // todo: ...
  assign tok_addr_o = addr_q;
  assign tok_endp_o = endp_q;
  // assign tok_addr_o = token_data[6:0];
  // assign tok_endp_o = token_data[10:7];
  assign hsk_recv_o = hsk_recv_q;
  assign usb_recv_o = usb_recv_q;

  // Raw USB packets (including PID & CRC bytes)
  assign raw_tvalid_o = rx_tvalid;
  assign raw_tlast_o = rx_tlast;
  assign raw_tdata_o = rx_tdata;

  assign m_tvalid = rx_tvalid;
  assign m_tkeep = rx_tkeep;
  assign m_tlast = rx_tlast;
  assign m_tuser = rx_tuser;
  assign m_tdata = rx_tdata;


  // -- Capture Incoming USB Packets -- //

  // This signal goes high if 'RxActive' (or 'dir') de-asserts during packet Rx
  reg end_q, nxt_q;
  wire rx_end_w =
       dir_q && ulpi_dir && !ulpi_nxt && ulpi_data[5:4] != RxActive ||
       !ibuf_dir && ulpi_dir;

  // todo: is this legit !?
  wire rx_end_x =
       ibuf_dir && ulpi_dir && !ibuf_nxt && cyc_q && ibuf_data[5:4] != RxActive ||
       !ibuf_dir && ulpi_dir;

  wire rx_cmd_w = dir_q && ulpi_dir && !ulpi_nxt && !cyc_q;

  always @(posedge clock) begin
    // end_q <= rx_end_w && !rx_cmd_w;
    // todo: is this legit !?
    end_q <= (rx_end_w || rx_end_x) && !rx_cmd_w;
    dir_q <= ulpi_dir;
    nxt_q <= ulpi_nxt;

    if (reset) begin
      cyc_q <= 1'b0;
      pid_q <= 1'b0;
      dat_q <= 8'bx;

      rx_tvalid <= 1'b0;
      rx_tkeep <= 1'bx;
      rx_tlast <= 1'bx;
      rx_tuser <= 4'ha;
      rx_tdata <= 8'hx;
    end else begin
      if (cyc_q && end_q) begin
        cyc_q <= 1'b0;
        pid_q <= 1'b0;
        dat_q <= 8'bx;

        rx_tvalid <= 1'b1;
        rx_tkeep <= 1'b0;
        rx_tlast <= 1'b1;
        // rx_tuser <= rx_tuser;
        rx_tdata <= 8'bx;
      end else if (dir_q && ulpi_dir && ulpi_nxt) begin
        cyc_q <= 1'b1;
        pid_q <= cyc_q;
        dat_q <= ulpi_data;

        if (!cyc_q) begin
          rx_tvalid <= 1'b0;
          rx_tkeep  <= 1'bx;
          rx_tlast  <= 1'bx;
          // rx_tuser  <= rx_tuser;
          rx_tdata  <= 8'hx;
        end else begin
          rx_tvalid <= 1'b1;
          // rx_tkeep  <= pid_q && !(end_q || rx_end_w);
          // todo: this is not legit !?
          rx_tkeep  <= pid_q && !(end_q || rx_end_w || rx_end_x);
          rx_tlast  <= 1'b0;
          // rx_tuser  <= pid_q ? rx_tuser : dat_q[3:0];
          rx_tdata  <= dat_q;
        end
      end else begin
        rx_tvalid <= 1'b0;
        rx_tkeep  <= 1'b0;
        rx_tlast  <= 1'b0;
        // rx_tuser  <= rx_tuser;
        rx_tdata  <= 8'bx;
      end
    end

    // Capture the transaction PID
    if (cyc_q && !pid_q) begin
      rx_tuser <= dat_q[3:0];
    end
  end


  // -- USB PID Parser -- //

  // assign istoken_w = rx_pid_pw[1:0] == PID_TOKEN && rx_pid_pw[3:2] != TOK_SOF ||
  //                    rx_pid_pw == {SPC_PING, PID_SPECIAL};
  assign istoken_w = rx_pid_pw[1:0] == PID_TOKEN || rx_pid_pw == {SPC_PING, PID_SPECIAL};
  assign pid_vld_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_pw == rx_pid_nw;
  assign rx_pid_pw = ulpi_data[3:0];
  assign rx_pid_nw = ~ulpi_data[7:4];

  // Decode USB handshake packets
  always @(posedge clock) begin
    if (reset) begin
      hsk_q <= 1'b0;
    end else begin
      if (pid_vld_w && !cyc_q) begin
        hsk_q <= rx_pid_pw[1:0] == PID_HANDSHAKE;
      end else if (end_q) begin
        hsk_q <= 1'b0;
      end
    end
  end

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    if (reset) begin
      tok_q <= 1'b0;
      sof_q <= 1'b0;
      low_q <= 1'b1;
      endp_q <= 0;
      addr_q <= 0;
      token_data <= 11'd0;
    end else begin
      // Decode USB Start-of-Frame (SOF) Packets
      if (!tok_q && pid_vld_w && rx_pid_pw[3:2] == TOK_SOF && !pid_q) begin
        sof_q <= 1'b1;
      end else if (end_q) begin
        sof_q <= 1'b0;
      end

      if (!tok_q && pid_vld_w && istoken_w && !pid_q) begin
        tok_q <= 1'b1;
        low_q <= 1'b1;
      end else if (tok_q && ulpi_nxt) begin
        if (low_q && !sof_q) begin
          {endp_q[0], addr_q} <= ulpi_data;
        end else if (!sof_q) begin
          endp_q[3:1] <= ulpi_data[2:0];
        end
        token_data[7:0] <= low_q ? ulpi_data : token_data[7:0];
        token_data[10:8] <= low_q ? token_data[10:8] : ulpi_data[2:0];
        low_q <= ~low_q;
        tok_q <= 1'b1;
      end else if (end_q) begin
        tok_q <= 1'b0;
        low_q <= 1'bx;
      end else begin
        token_data <= token_data;
        low_q <= low_q;
      end
    end
  end

  always @(posedge clock) begin
    tok_recv_q <= tok_q && !sof_q && end_q && rx_crc5_w == dat_q[7:3];
    sof_recv_q <= sof_q && end_q && rx_crc5_w == dat_q[7:3];  // todo: ...
    hsk_recv_q <= hsk_q && end_q;
    usb_recv_q <= cyc_q && end_q && !tok_q && crc16_q == 16'h800d;  // todo: ...
  end


  // -- Early CRC16 calculation -- //

  assign rx_crc5_w = crc5(token_data);
  assign crc16_w   = crc16(ulpi_data, crc16_q);

  always @(posedge clock) begin
    if (!cyc_q) begin
      crc16_q <= 16'hffff;
    end else if (cyc_q && ulpi_nxt) begin
      crc16_q <= crc16_w;
    end else begin
      crc16_q <= crc16_q;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      crc_error_flag <= 1'b0;
      crc_valid_flag <= 1'b0;
    end else if (tok_q && end_q) begin
      crc_error_flag <= rx_crc5_w != dat_q[7:3];
      crc_valid_flag <= rx_crc5_w == dat_q[7:3];
    end else if (!hsk_q && cyc_q && end_q) begin
      crc_error_flag <= crc16_q != 16'h800d;
      crc_valid_flag <= crc16_q == 16'h800d;
    end else begin
      crc_valid_flag <= 1'b0;
    end
  end


endmodule  // ulpi_decoder


module drop_the_last_two
 ( input clock,
   input reset,

   input ulpi_dir,
   input ulpi_nxt,
   input [7:0] ulpi_data,

   output crc_error_o,
   output crc_valid_o,
    output usb_sof_o,
    output dec_idle_o,

    output tok_recv_o,
    output tok_ping_o,
    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,
    output hsk_recv_o,
    output usb_recv_o,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [3:0] m_tuser,
    output [7:0] m_tdata
   );

  `include "usb_crc.vh"

  // -- Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] SPC_PING = 2'b01;

  localparam [1:0] PID_SPECIAL = 2'b00;
  localparam [1:0] PID_TOKEN = 2'b01;
  localparam [1:0] PID_HANDSHAKE = 2'b10;
  localparam [1:0] PID_DATA = 2'b11;

  // USB 'RX_CMD[5:4]' bits
  localparam [1:0] RxActive = 2'b01;
  localparam [1:0] RxError = 2'b11;


  // -- Signals & State -- //

  // USB packet-receive signals
  reg tok_recv_q, hsk_recv_q, usb_recv_q, sof_recv_q;
  reg tvalid, tlast, tkeep;
  reg [3:0] tuser;
  reg [7:0] tdata;

  // CRC16 calculation & framing signals
  reg crc_error_flag, crc_valid_flag;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_w;
  reg  [10:0] token_data;
  wire [ 4:0] rx_crc5_w;

  assign crc_error_o = crc_error_flag;
  assign crc_valid_o = crc_valid_flag;
  assign usb_sof_o   = sof_recv_q;
  assign dec_idle_o  = ~cyc_q;

  assign tok_recv_o = tok_recv_q;
  assign tok_ping_o = 1'b0;  // todo: ...
  assign tok_addr_o = addr_q;
  assign tok_endp_o = endp_q;
  assign hsk_recv_o = hsk_recv_q;
  assign usb_recv_o = usb_recv_q;

  assign m_tvalid = tvalid;
  assign m_tlast  = tlast;
  assign m_tkeep  = tkeep;
  assign m_tuser  = tuser;
  assign m_tdata  = tdata;


  // -- Pipeline Control -- //

  reg dir_q, cyc_q, end_q, tok_q, hsk_q;
  wire rx_end_w, pid_vld_w, istoken_w;
  wire [3:0] rx_pid_pw, rx_pid_nw;

  assign rx_end_w  = !ulpi_dir || ulpi_dir && !ulpi_nxt && ulpi_data[5:4] != 2'b01;
  assign rx_pid_pw = ulpi_data[3:0];
  assign rx_pid_nw = ~ulpi_data[7:4];

  assign pid_vld_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_pw == rx_pid_nw;
  assign istoken_w = rx_pid_pw[1:0] == PID_TOKEN || rx_pid_pw == {SPC_PING, PID_SPECIAL};

  // Frames a USB packet-receive transfer cycle.
  always @(posedge clock) begin
    dir_q <= ulpi_dir;
    end_q <= rx_end_w;

    if (reset || rx_end_w) begin
      cyc_q <= 1'b0;
      tok_q <= 1'b0;
      hsk_q <= 1'b0;
    end else if (ulpi_dir && ulpi_nxt && dir_q && pid_vld_w) begin
      cyc_q <= 1'b1;
      if (rx_pid_pw[1:0] == PID_HANDSHAKE) begin
        hsk_q <= 1'b1;
      end
      if (istoken_w && !cyc_q && !end_q) begin
        tok_q <= 1'b1;
      end
    end

    if (reset) begin
      tuser <= 4'ha;
    end else if (!cyc_q && ulpi_dir && ulpi_nxt && dir_q && pid_vld_w) begin
      tuser <= rx_pid_pw;
    end
  end

  always @(posedge clock) begin
    if (cyc_q && rx_end_w && rx_crc5_w == dat_q[7:3]) begin
      tok_recv_q <= tok_q && !sof_q;
      sof_recv_q <= sof_q;
    end else begin
      tok_recv_q <= 1'b0;
      sof_recv_q <= 1'b0;
    end      
    hsk_recv_q <= hsk_q && rx_end_w;
    usb_recv_q <= cyc_q && !tok_q && rx_end_w && crc16_q == 16'h800d;  // todo: ...
  end


  //
  // Stage I: Capture registers
  // Note: When receiving USB packets, capture data whenever 'nxt' is asserted,
  // and drop the data when the transfer ends.
  reg stb_q;
  reg [7:0] dat_q;

  always @(posedge clock) begin
    if (reset) begin
      stb_q <= 1'b0;
      dat_q <= 'bx;
    end else begin
      if (dir_q && ulpi_dir && ulpi_nxt) begin
        stb_q <= cyc_q;
        dat_q <= ulpi_data;
      end else begin
        stb_q <= stb_q && cyc_q && !rx_end_w;
      end
    end
  end

  //
  // Stage II: Pipeline registers
  // Note: Fills up the registers as 'nxt' clocks additional data in, and drops
  // stored data when a transaction ends.
  reg vld_q;
  reg [7:0] out_q;

  always @(posedge clock) begin
    if (reset || rx_end_w) begin
      vld_q <= 1'b0;
      out_q <= 'bx;
    end else if (ulpi_nxt) begin
      vld_q <= stb_q;
      out_q <= dat_q;
    end
  end

  //
  // Stage III: Output registers
  // Note: Only transfers-out data when there are two bytes stored in the input
  // registers/pipeline.
  always @(posedge clock) begin
    if (reset) begin
      tvalid <= 1'b0;
      tlast  <= 1'b0;
      tkeep  <= 1'b0;
      tdata  <= 'bx;
    end else begin
      tvalid <= cyc_q;
      tlast  <= cyc_q && rx_end_w;
      if (ulpi_nxt && stb_q && vld_q) begin
        tkeep <= 1'b1;
        tdata <= out_q;
      end else begin
        tkeep <= 1'b0;
        tdata <= 'bx;
      end
    end
  end


  // -- USB Token Handling -- //

  reg sof_q, low_q;
  reg [3:0] endp_q;
  reg [6:0] addr_q;
  wire [10:0] token_w;

  assign token_w = {dat_q, out_q}; // endp_q[0], addr_q};

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    if (reset) begin
      sof_q <= 1'b0;
      low_q <= 1'b1;
      endp_q <= 0;
      addr_q <= 0;
    end else begin
      // Decode USB Start-of-Frame (SOF) Packets
      if (!tok_q && pid_vld_w && rx_pid_pw[3:2] == TOK_SOF) begin
        sof_q <= 1'b1;
      end else if (end_q) begin
        sof_q <= 1'b0;
      end

      if (!tok_q && pid_vld_w && istoken_w) begin
        low_q <= 1'b1;
      end else if (tok_q && ulpi_nxt) begin
        if (low_q && !sof_q) begin
          {endp_q[0], addr_q} <= ulpi_data;
        end else if (!sof_q) begin
          endp_q[3:1] <= ulpi_data[2:0];
        end
        low_q <= ~low_q;
      end
    end
  end


  // -- Early CRC16 calculation -- //

  assign rx_crc5_w = crc5(token_w);
  assign crc16_w   = crc16(ulpi_data, crc16_q);

  always @(posedge clock) begin
    if (!cyc_q) begin
      crc16_q <= 16'hffff;
    end else if (cyc_q && ulpi_nxt) begin
      crc16_q <= crc16_w;
    end else begin
      crc16_q <= crc16_q;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      crc_error_flag <= 1'b0;
      crc_valid_flag <= 1'b0;
    end else if (rx_end_w && cyc_q) begin
      if (!hsk_q && !tok_q) begin
        crc_error_flag <= crc16_q != 16'h800d;
        crc_valid_flag <= crc16_q == 16'h800d;
      end else if (tok_q) begin
        crc_error_flag <= rx_crc5_w != dat_q[7:3];
        crc_valid_flag <= rx_crc5_w == dat_q[7:3];
      end
    end else begin
      crc_valid_flag <= 1'b0;
    end
  end


endmodule // drop_the_last_two

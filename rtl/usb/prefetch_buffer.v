`timescale 1ns / 100ps
/**
 * Simple prefech buffer that supports up to one read and one write, at the same
 * time.
 * Note(s):
 *  - double-buffered, in each direction;
 *  - each packet can be less than 'LENGTH';
 *  - only "releases" a packet once CRC passes;
 */
module prefetch_buffer
  #( parameter USE_SIMPLE_PREFETCH_BUFFER = 1,
     parameter USB_MAX_PACKET_SIZE = 512, // For HS-mode
     parameter WIDTH = 8,
     localparam MSB = WIDTH - 1,
     parameter LENGTH = 512,
     localparam LBITS = $clog2(LENGTH),
     localparam LSB = LBITS - 1,
     localparam [LSB:0] LZERO = {LBITS{1'b0}}
     )
  (
   input clock,
   input reset,

   // -- Control Signals -- //
   output tx_ready_o,  // Can TX at least one packet
   input tx_done_i,
   input tx_abort_i,

   output rx_ready_o,  // Can RX at least one packet
   input rx_done_i,
   input rx_abort_i,

   // -- To/from the bus-attached device -- //
   input dev_s_tvalid_i,
   output dev_s_tready_o,
   input dev_s_tlast_i,
   input [MSB:0] dev_s_tdata_i,

   output dev_m_tvalid_o,
   input dev_m_tready_i,
   output dev_m_tkeep_o,
   output dev_m_tlast_o,
   output [MSB:0] dev_m_tdata_o,

   // -- To/from the data-bus -- //
   input bus_s_tvalid_i,
   output bus_s_tready_o,
   input bus_s_tlast_i,
   input bus_s_tkeep_i,
   input [MSB:0] bus_s_tdata_i,

   output bus_m_tvalid_o,
   input bus_m_tready_i,
   output bus_m_tkeep_o,
   output bus_m_tlast_o,
   output [MSB:0] bus_m_tdata_o
   );


  reg [LSB:0] tx_len0, tx_len1, rx_len0, rx_len1;
  reg tx_rdy0, tx_rdy1, rx_rdy0, rx_rdy1;


  assign tx_ready_o = tx_rdy0 | tx_rdy1;
  assign rx_ready_o = rx_rdy0 | rx_rdy1;


  generate if (USE_SIMPLE_PREFETCH_BUFFER) begin : g_simple
    //
    //  Full-Duplex using 2x SRAMs
    ///
    localparam DEPTH = LENGTH * 2;
    localparam ABITS = LBITS + 1;
    localparam ASB = LBITS;
    localparam [ASB:0] AZERO = {ABITS{1'b0}};
    localparam OUTREG = ABITS < 5 ? 1 : 2;


    packet_fifo
      #( .OUTREG(OUTREG),
         .WIDTH(WIDTH),
         .DEPTH(DEPTH),
         .USE_LASTS(1),
         .USE_LENGTH(1),
         .MAX_LENGTH(USB_MAX_PACKET_SIZE)
         )
    FIFO_RX0
      (
       .clock(clock),
       .reset(reset),

       .level_o(rx_level),
       .drop_i(rx_abort_i),
       .save_i(rx_done_i),
       .redo_i(1'b0),
       .next_i(1'b0), // Todo

       .valid_i(bus_s_tvalid_i),
       .ready_o(bus_s_tready_o),
       .last_i(bus_s_tlast_i),
       .data_i(bus_s_tdata_i),

       .valid_o(dev_m_tvalid_o),
       .ready_i(dev_m_tready_i),
       .last_o(dev_m_tlast_o),
       .data_o(dev_m_tdata_o)
       );

    packet_fifo
      #( .OUTREG(OUTREG),
         .WIDTH(WIDTH),
         .DEPTH(DEPTH),
         .USE_LASTS(1),
         .USE_LENGTH(1),
         .MAX_LENGTH(USB_MAX_PACKET_SIZE)
         )
    FIFO_TX0
      (
       .clock(clock),
       .reset(reset),

       .level_o(tx_level),
       .drop_i(1'b0),
       .save_i(1'b0), // Todo
       .redo_i(tx_abort_i),
       .next_i(tx_done_i),

       .valid_i(dev_s_tvalid_i),
       .ready_o(dev_s_tready_o),
       .last_i(dev_s_tlast_i),
       .data_i(dev_s_tdata_i),

       .valid_o(bus_m_tvalid_o),
       .ready_i(bus_m_tready_i),
       .last_o(bus_m_tlast_o),
       .data_o(bus_m_tdata_o)
       );


  end else begin : g_complex
    //
    //  Half-Duplex using just one SRAM
    ///
    localparam SIZE = LENGTH * 4;
    localparam ABITS = LBITS + 2;
    localparam ASB = LBITS + 1;
    localparam [ASB:0] AZERO = {ABITS{1'b0}};

  // Double-buffered, in each direction
  reg [ASB:0] rd_addr, wr_addr;
  reg [LSB:0] tx_len0, tx_len1, rx_len0, rx_len1;
  reg tx_rdy0, tx_rdy1, rx_rdy0, rx_rdy1;
  reg tx_bank, rx_bank;
  reg [MSB:0] sram [0:SIZE-1];


  always @(posedge clock) begin
    if (reset) begin
      tx_len0 <= LZERO;
      tx_rdy0 <= 1'b0;
      tx_len1 <= LZERO;
      tx_rdy1 <= 1'b0;
      tx_bank <= 1'b0;

      rx_len0 <= LZERO;
      rx_rdy0 <= 1'b1;
      rx_len1 <= LZERO;
      rx_rdy1 <= 1'b1;
      rx_bank <= 1'b0;
    end else begin

      if (tx_done_i) begin
        // Todo: ...
      end

    end
  end


  end
  endgenerate


endmodule  /* prefetch_buffer */

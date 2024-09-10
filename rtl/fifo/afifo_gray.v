/////////////////////////////////////////////////////////////////////
////                                                             ////
////  Universal FIFO Dual Clock, gray encoded                    ////
////                                                             ////
////                                                             ////
////  Author: Rudolf Usselmann                                   ////
////          rudi@asics.ws                                      ////
////                                                             ////
////                                                             ////
////  D/L from: http://www.opencores.org/cores/generic_fifos/    ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2000-2002 Rudolf Usselmann                    ////
////                         www.asics.ws                        ////
////                         rudi@asics.ws                       ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
/*

Description
===========

I/Os
----
rd_clk   - Read Port Clock
wr_clk   - Write Port Clock
rst      - low active, either sync. or async. master reset (see below how to select)
clr      - synchronous clear (just like reset but always synchronous), high active
re       - read enable, synchronous, high active
we       - read enable, synchronous, high active
din      - Data Input
dout     - Data Output

full     - Indicates the FIFO is full (driven at the rising edge of wr_clk)
empty    - Indicates the FIFO is empty (driven at the rising edge of rd_clk)

wr_level - indicates the FIFO level:
            - 2'b00  0-25%     full
            - 2'b01  25-50%    full
            - 2'b10  50-75%    full
            - 2'b11  %75-100%  full

rd_level - indicates the FIFO level:
            - 2'b00  0-25%     empty
            - 2'b01  25-50%    empty
            - 2'b10  50-75%    empty
            - 2'b11  %75-100%  empty

Status Timing
-------------
All status outputs are registered. They are asserted immediately
as the full/empty condition occurs, however, there is a 2 cycle
delay before they are de-asserted once the condition is not true
anymore.

Parameters
----------
The FIFO takes 2 parameters:
 + WIDTH -- Data bus width; and
 + ABITS -- Address bus width (which determines the FIFO size by evaluating
            2^ABITS).

Synthesis Results
-----------------
In a Spartan 2e a 8 bit wide, 8 entries deep FIFO, takes 97 LUTs and runs
at about 113 MHz (IO insertion disabled).

Misc
----
This design assumes you will do appropriate status checking externally.

IMPORTANT ! writing while the FIFO is full or reading while the FIFO is
empty will place the FIFO in an undefined state.

*/

`timescale 1ns / 100ps
module afifo_gray #(
    parameter  integer WIDTH = 16,
    localparam integer MSB   = WIDTH - 1,
    parameter  integer ABITS = 4,
    localparam integer ASB   = ABITS - 1,
    localparam integer DEPTH = 1 << ABITS
) (  // System clocks and resets:
    input rd_clk_i,
    input wr_clk_i,
    input reset_ni,

    // Data signals:
    input wr_en_i,
    input [MSB:0] wr_data_i,
    input rd_en_i,
    output [MSB:0] rd_data_o,

    // FIFO status flags:
    output wfull_o,
    output rempty_o
);

  reg wfull_q = 1'b0;
  reg rempty_q = 1'b1;

  assign wfull_o  = wfull_q;
  assign rempty_o = rempty_q;

  //-------------------------------------------------------------------------
  //  Local Wires
  //-------------------------------------------------------------------------

  wire [ABITS:0] wp_bin_next, wp_gray_next;
  wire [ABITS:0] rp_bin_next, rp_gray_next;

  reg [ABITS:0] wp_bin = 0, wp_gray = 0;
  reg [ABITS:0] rp_bin = 0, rp_gray = 0;

  (* ASYNC_REG = "TRUE" *)
  reg [ABITS:0] wp_s = 0;
  (* ASYNC_REG = "TRUE" *)
  reg [ABITS:0] rp_s = 0;

  wire [ABITS:0] wp_bin_x, rp_bin_x;

  reg rd_rst = 1'b1, wr_rst = 1'b1;
  reg rd_rst_r = 1'b1, wr_rst_r = 1'b1;

  //-------------------------------------------------------------------------
  //  Reset Logic
  //-------------------------------------------------------------------------

  always @(posedge rd_clk_i or negedge reset_ni) begin
    if (!reset_ni) begin
      rd_rst_r <= 1'b1;
      rd_rst   <= 1'b1;
    end else begin
      rd_rst_r <= 1'b0;
      if (!rd_rst_r) begin
        rd_rst <= 1'b0;  // Release Reset
      end
    end
  end

  always @(posedge wr_clk_i or negedge reset_ni) begin
    if (!reset_ni) begin
      wr_rst_r <= 1'b1;
      wr_rst   <= 1'b1;
    end else begin
      wr_rst_r <= 1'b0;
      if (!wr_rst_r) begin
        wr_rst <= 1'b0;  // Release Reset
      end
    end
  end

  //-------------------------------------------------------------------------
  //  Memory Block
  //-------------------------------------------------------------------------

  reg [MSB:0] sram[0:DEPTH-1];

  assign rd_data_o = sram[rp_bin[ASB:0]];

  always @(posedge wr_clk_i) begin
    if (wr_en_i && !wr_rst) begin
      sram[wp_bin[ASB:0]] <= wr_data_i;
    end
  end

  //-------------------------------------------------------------------------
  //  Read/Write Pointers Logic
  //-------------------------------------------------------------------------

  assign wp_bin_next  = wp_bin + {{ABITS{1'b0}}, 1'b1};
  assign wp_gray_next = wp_bin_next ^ {1'b0, wp_bin_next[ABITS:1]};

  always @(posedge wr_clk_i) begin
    if (wr_rst) begin
      wp_bin  <= {ABITS + 1{1'b0}};
      wp_gray <= {ABITS + 1{1'b0}};
    end else if (wr_en_i) begin
      wp_bin  <= wp_bin_next;
      wp_gray <= wp_gray_next;
    end
  end

  assign rp_bin_next  = rp_bin + {{ABITS{1'b0}}, 1'b1};
  assign rp_gray_next = rp_bin_next ^ {1'b0, rp_bin_next[ABITS:1]};

  always @(posedge rd_clk_i) begin
    if (rd_rst) begin
      rp_bin  <= {ABITS + 1{1'b0}};
      rp_gray <= {ABITS + 1{1'b0}};
    end else if (rd_en_i) begin
      rp_bin  <= rp_bin_next;
      rp_gray <= rp_gray_next;
    end
  end

  //-------------------------------------------------------------------------
  //  Synchronization Logic
  //-------------------------------------------------------------------------

  always @(posedge rd_clk_i) begin
    wp_s <= wp_gray;  // write pointer -> read domain
  end

  always @(posedge wr_clk_i) begin
    rp_s <= rp_gray;  // read pointer -> write domain
  end

  //-------------------------------------------------------------------------
  //  Registered Wfull_q & Rempty_q Flags
  //-------------------------------------------------------------------------

  // -- Convert Gray to binary -- //
  assign wp_bin_x = wp_s ^ {1'b0, wp_bin_x[ABITS:1]};
  assign rp_bin_x = rp_s ^ {1'b0, rp_bin_x[ABITS:1]};

  always @(posedge rd_clk_i) begin
    if (!reset_ni) begin
      rempty_q <= 1'b1;
    end else begin
      rempty_q <= wp_s == rp_gray || rd_en_i && wp_s == rp_gray_next;
    end
  end

  // todo: worth using a cheaper (capacity-1) comparison?
  wire full_curr = wp_bin[ASB:0] == rp_bin_x[ASB:0] && wp_bin[ABITS] != rp_bin_x[ABITS];
  wire full_next = wr_en_i && wp_bin_next[ASB:0] == rp_bin_x[ASB:0] &&
     wp_bin_next[ABITS] != rp_bin_x[ABITS];

  always @(posedge wr_clk_i) begin
    if (!reset_ni) begin
      wfull_q <= 1'b0;
    end else begin
      wfull_q <= full_curr || full_next;
    end
  end

  //-------------------------------------------------------------------------
  //  Sanity Check
  //-------------------------------------------------------------------------

  always @(posedge wr_clk_i) begin
    if (wr_en_i && wfull_q) begin
      $display("%m WARNING: Writing while FIFO is FULL (%t)", $time);
    end
  end

  always @(posedge rd_clk_i) begin
    if (rd_en_i && rempty_q) begin
      $display("%m WARNING: Reading while FIFO is EMPTY (%t)", $time);
    end
  end

endmodule  /* afifo_gray */

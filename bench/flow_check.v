`timescale 1ns / 100ps
module axis_flow_check
#( parameter WIDTH = 8
) (
    input clock,
    input reset,

    input axis_tvalid,
    input axis_tready,
    input axis_tlast,
    input [WIDTH-1:0] axis_tdata
 );

  localparam MSB = WIDTH - 1;

`ifdef __icarus
  reg prev_tvalid, prev_tlast, prev_tready;
  reg [MSB:0] prev_tdata;

   
  always @(posedge clock) begin
    if (reset) begin
      prev_tvalid <= 1'b0;
      prev_tready <= 1'b0;
      prev_tlast <= 1'b0;
      prev_tdata <= 'bx;
    end else begin
      prev_tvalid <= axis_tvalid;
      prev_tready <= axis_tready;
      prev_tlast  <= axis_tlast;
      prev_tdata  <= axis_tdata;
      //
      // RULES:
      //
      //  - once 'tvalid' is asserted, neither 'tvalid', 'tlast', nor 'tdata'
      //    can change until 'tready' is asserted
      //
      if (prev_tvalid && !prev_tready) begin
        if (axis_tvalid != prev_tvalid) $error("%10t: 'tvalid' de-asserted without 'tready'", $time);
        if (axis_tlast != prev_tlast) $error("%10t: 'tlast' changed without 'tready'", $time);
        if (axis_tdata != prev_tdata) $error("%10t: 'tdata' changed without 'tready'", $time);
      end
    end
  end
`endif

   
endmodule // axis_flow_check

module ulpi_flow_check
(
    input ulpi_clk,
    input ulpi_rst_n,
    input ulpi_dir,
    input ulpi_nxt,
    input ulpi_stp,
    input [7:0] ulpi_data
 );

`ifdef __icarus
  reg prev_dir, prev_nxt, prev_stp;
  reg [7:0] prev_data;

   
  always @(posedge ulpi_clk) begin
    if (!ulpi_rst_n) begin
      prev_dir  <= 1'b0;
      prev_nxt  <= 1'b0;
      prev_stp  <= 1'b0;
      prev_data <= 'bx;
    end else begin
      prev_dir  <= ulpi_dir;
      prev_nxt  <= ulpi_nxt;
      prev_stp  <= ulpi_stp;
      prev_data <= ulpi_data;
      //
      // RULES:
      //
      //  - PHY must assert both 'dir' and 'nxt' when starting a bus transfer,
      //    then deasserts 'nxt' the next cycle (during "bus-turnaround")
      //  - link must not change 'data' when, driving the bus and 'nxt' is low
      //    can change until 'tready' is asserted
      //  - link "idles" the bus by driving 'data = 8'h00' onto the bus, when
      //    'dir' is low -- how to check !?
      //
      if (!prev_dir && !ulpi_dir) begin // RECV
        if (!prev_nxt && prev_data != 8'h00 && prev_data != ulpi_data)
          $error("%10t: Rx 'data' changed while 'nxt' de-asserted", $time);
      end

      /*
      // todo: needs more work, due to the 'RX_CMD' packets ...
      if (prev_dir && ulpi_dir) begin // SEND
        if (!prev_nxt && prev_data != ulpi_data)
          $error("%10t: Tx 'data' changed while 'nxt' de-asserted", $time);
      end
      */

      // PHY checks
      if (!prev_dir && !prev_data == 8'h00) begin
        if (ulpi_dir && !ulpi_nxt) $error("%10t: 'nxt' not asserted with 'dir'", $time);
      end
    end
  end
`endif

   
endmodule // ulpi_flow_check

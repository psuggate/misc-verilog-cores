`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module Name: arch_cdc_array
// Project Name: axis_usbd
//
// License: MIT
//  Copyright (c) 2021 Dmitry Matyunin
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
// 
//////////////////////////////////////////////////////////////////////////////////

//
// Clock-Domain Crossing (synchroniser) Array
//
module arch_cdc_array #(
    parameter FPGA_VENDOR = "xilinx",
    parameter FPGA_FAMILY = "7series",
    parameter WIDTH = 2
) (
    input wire src_clk,
    input wire [WIDTH-1:0] src_data,
    input wire dst_clk,
    output wire [WIDTH-1:0] dst_data
);

  generate
    if ((FPGA_VENDOR == "xilinx") && (FPGA_FAMILY == "7series")) begin : g_xilinx_cdc_inst
      xpm_cdc_array_single #(
          .DEST_SYNC_FF(3),
          .INIT_SYNC_FF(0),
          .SIM_ASSERT_CHK(0),
          .SRC_INPUT_REG(1),
          .WIDTH(WIDTH)
      ) xpm_cdc_array_single_inst (
          .dest_out(dst_data),
          .dest_clk(dst_clk),
          .src_clk (src_clk),
          .src_in  (src_data)
      );
    end else begin : g_generic_cdc_synch

      (* NOMERGE = "TRUE" *) reg [WIDTH-1:0] data_0;

      always @(posedge src_clk) begin
        data_0 <= src_data;
      end

      (* NOMERGE = "TRUE" *) reg [WIDTH-1:0] data_1, data_2, data_3;

      assign dst_data = data_3;

      always @(posedge dst_clk) begin
        {data_3, data_2, data_1} <= {data_2, data_1, data_0};
      end

    end
  endgenerate

endmodule

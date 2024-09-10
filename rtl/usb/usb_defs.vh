// USB PID values (from Sec. 8.3, USB 2.0 spec.)
`define USBPID_OUT      4'b0001
`define USBPID_IN       4'b1001
`define USBPID_SOF      4'b0101
`define USBPID_SETUP    4'b1101
`define USBPID_DATA0    4'b0011
`define USBPID_DATA1    4'b1011
`define USBPID_DATA2    4'b0111
`define USBPID_MDATA    4'b1111
`define USBPID_ACK      4'b0010
`define USBPID_NAK      4'b1010
`define USBPID_STALL    4'b1110
`define USBPID_NYET     4'b0110
`define USBPID_PRE      4'b1100
`define USBPID_ERR      4'b1100
`define USBPID_SPLIT    4'b1000
`define USBPID_PING     4'b0100
`define USBPID_RESERVED 4'b0000


`ifdef __icarus_potatio
  localparam [7:0] COUNT_2_5_US = 14;
  localparam [5:0] COUNT_100_US = 3;
  localparam [8:0] COUNT_1_0_MS = 39;
`else  /* !__icarus */
  localparam [7:0] COUNT_2_5_US = 149;
  localparam [5:0] COUNT_100_US = 39;
  localparam [8:0] COUNT_1_0_MS = 399;
`endif /* !__icarus */


function [4:0] crc5;
  input [10:0] x;
  begin
    crc5[4] = ~(1'b1 ^ x[10] ^ x[7] ^ x[5] ^ x[4] ^ x[1] ^ x[0]);
    crc5[3] = ~(1'b1 ^ x[9] ^ x[6] ^ x[4] ^ x[3] ^ x[0]);
    crc5[2] = ~(1'b1 ^ x[10] ^ x[8] ^ x[7] ^ x[4] ^ x[3] ^ x[2] ^ x[1] ^ x[0]);
    crc5[1] = ~(1'b0 ^ x[9] ^ x[7] ^ x[6] ^ x[3] ^ x[2] ^ x[1] ^ x[0]);
    crc5[0] = ~(1'b1 ^ x[8] ^ x[6] ^ x[5] ^ x[2] ^ x[1] ^ x[0]);
  end
endfunction

function [15:0] crc16;
  input [7:0] d;
  input [15:0] c;
  begin
    crc16[0] = d[0] ^ d[1] ^ d[2] ^ d[3] ^ d[4] ^ d[5] ^ d[6] ^ d[7] ^ c[8] ^
               c[9] ^ c[10] ^ c[11] ^ c[12] ^ c[13] ^ c[14] ^ c[15];
    crc16[1] = d[0] ^ d[1] ^ d[2] ^ d[3] ^ d[4] ^ d[5] ^ d[6] ^ c[9] ^ c[10] ^
               c[11] ^ c[12] ^ c[13] ^ c[14] ^ c[15];
    crc16[2] = d[6] ^ d[7] ^ c[8] ^ c[9];
    crc16[3] = d[5] ^ d[6] ^ c[9] ^ c[10];
    crc16[4] = d[4] ^ d[5] ^ c[10] ^ c[11];
    crc16[5] = d[3] ^ d[4] ^ c[11] ^ c[12];
    crc16[6] = d[2] ^ d[3] ^ c[12] ^ c[13];
    crc16[7] = d[1] ^ d[2] ^ c[13] ^ c[14];
    crc16[8] = d[0] ^ d[1] ^ c[0] ^ c[14] ^ c[15];
    crc16[9] = d[0] ^ c[1] ^ c[15];
    crc16[10] = c[2];
    crc16[11] = c[3];
    crc16[12] = c[4];
    crc16[13] = c[5];
    crc16[14] = c[6];
    crc16[15] = d[0] ^ d[1] ^ d[2] ^ d[3] ^ d[4] ^ d[5] ^ d[6] ^ d[7] ^ c[7] ^
                c[8] ^ c[9] ^ c[10] ^ c[11] ^ c[12] ^ c[13] ^ c[14] ^ c[15];
  end
endfunction

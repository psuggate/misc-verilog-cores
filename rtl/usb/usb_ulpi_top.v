`timescale 1ns / 100ps
module usb_ulpi_top
  #( parameter USE_EP2_IN = 1,
     parameter USE_EP1_OUT = 1,
     )
  (
    // Global, asynchronous reset
    input  areset_n,
    output reset_no,

    // UTMI Low Pin Interface (ULPI)
    input ulpi_clock_i,
    input ulpi_dir_i,
    input ulpi_nxt_i,
    output ulpi_stp_o,
    inout [7:0] ulpi_data_io,

    // USB clock-domain clock & reset
    output usb_clock_o,
    output usb_reset_o,  // USB core is in reset state
   );


endmodule  /* usb_ulpi_top */

//
// Width (in bytes) of each burst "beat"
// Note: must not be wider than either agent in the transaction.
//
localparam [2:0] BURST_SIZE_1B = 3'b000;
localparam [2:0] BURST_SIZE_2B = 3'b001;
localparam [2:0] BURST_SIZE_4B = 3'b010;
localparam [2:0] BURST_SIZE_8B = 3'b011;
localparam [2:0] BURST_SIZE_16B = 3'b100;
localparam [2:0] BURST_SIZE_32B = 3'b101;
localparam [2:0] BURST_SIZE_64B = 3'b110;
localparam [2:0] BURST_SIZE_128B = 3'b111;

//
// Determines how the transaction-address is updated, after each beat of the
// burst.
//
localparam [1:0] BURST_TYPE_FIXED = 2'b00;
localparam [1:0] BURST_TYPE_INCR = 2'b01;
localparam [1:0] BURST_TYPE_WRAP = 2'b10;
localparam [1:0] BURST_TYPE_Reserved = 2'b11;

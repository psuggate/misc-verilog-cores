`timescale 1ns / 100ps
module ulpi_line_state #(
    parameter HIGH_SPEED = 1
) (
    input clock,
    input reset,

    input [1:0] LineState,
    output HighSpeed,
    input ulpi_dir,

    output phy_write_o,
    output phy_read_o,
    output phy_chirp_o,
    output phy_stop_o,
    input phy_busy_i,
    input phy_done_i,
    output [7:0] phy_addr_o,
    output [7:0] phy_data_o
);

  // -- Constants -- //

  localparam [3:0]
	LS_INIT = 4'h0, 
	LS_WRITE_REG = 4'h1,
	LS_STP = 4'h3,
	LS_RESET = 4'h4,
	LS_SUSPEND = 4'h5,
	LS_IDLE = 4'h6,
	LS_CHIRP_START = 4'h9,
	LS_CHIRP_STARTK = 4'hA,
	LS_CHIRPK = 4'hB,
	LS_CHIRPKJ = 4'hC,
	LS_SWITCH_FSSTART = 4'hD,
	LS_SWITCH_FS = 4'hE;


  // -- State & Signals -- //

  reg [3:0] xinit, xnext;
  reg dir_q, set_q;
  reg [7:0] adr_q, val_q;

  reg hs_enabled;


  // -- Output Assignments -- //

  assign phy_write_o = seq_q;
  assign phy_read_o  = 1'b0;
  assign phy_addr_o  = adr_q;
  assign phy_data_o  = val_q;

  assign HighSpeed   = hs_enabled;


  // -- USB & PHY Line States -- //

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
  end

  always @(posedge clock) begin
    if (reset || dir_q || ulpi_dir) begin
      set_q <= 1'b0;
      adr_q <= 8'hx;
      val_q <= 8'hx;
    end else begin
      case (xinit)
        // De-assert request after ACK
        LS_WRITE_REG: begin
          if (phy_busy_i) begin
            set_q <= 1'b0;
            adr_q <= 8'hx;
            val_q <= 8'bx;
          end
        end

        LS_INIT: begin
          set_q <= 1'b1;
          adr_q <= 8'h8A;
          val_q <= 8'h00;
        end

        LS_CHIRP_START: begin
          set_q <= 1'b1;
          adr_q <= 8'h84;
          val_q <= 8'b0_1_0_10_1_00;
        end

        LS_CHIRPKJ: begin
          if (chirp_kj_counter > 3 && state_counter > CHIRP_KJ_TIME) begin
            set_q <= 1'b1;
            adr_q <= 8'h84;
            val_q <= 8'b0_1_0_00_0_00;
          end else begin
            set_q <= 1'b0;
            adr_q <= 8'hx;
            val_q <= 8'bx;
          end
        end

        LS_SWITCH_FSSTART: begin
          set_q <= 1'b1;
          val_q <= 8'b0_1_0_00_1_01;
          adr_q <= 8'h84;
        end

        default: begin
          set_q <= 1'b0;
          adr_q <= 8'hx;
          val_q <= 8'hx;
        end
      endcase
    end
  end


  // -- ULPI Initialisation FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      xinit <= LS_INIT;
      xnext <= 4'hx;
    end else if (dir_q || ulpi_dir) begin
      // We are not driving //
      xinit <= xinit;
      xnext <= 4'hx;
    end else begin
      // We are driving //
      case (xinit)
        default: begin  // LS_INIT
          xinit <= LS_WRITE_REG;
          xnext <= LS_SWITCH_FSSTART;
        end

        LS_WRITE_REG: begin
          if (phy_done_i) begin
            xinit <= xnext;
            xnext <= 4'hx;
          end
        end

        LS_RESET: begin
          if (HIGH_SPEED == 1) begin
            xinit <= hs_enabled ? LS_SWITCH_FSSTART : LS_CHIRP_START;
          end else if (LineState != 2'b00) begin
            xinit <= LS_IDLE;
          end else begin
            xinit <= xinit;
          end
          xnext <= 4'hx;
        end

        LS_SUSPEND: begin
          xinit <= LineState != 2'b01 ? LS_IDLE : LS_SUSPEND;
          xnext <= 4'hx;
        end

        LS_IDLE: begin
          if (LineState == 2'b00 && state_counter > RESET_TIME) begin
            xinit <= LS_RESET;
          end else if (!hs_enabled && LineState == 2'b01 && state_counter > SUSPEND_TIME) begin
            xinit <= LS_SUSPEND;
          end
          xnext <= 4'hx;
        end

        LS_CHIRP_START: begin
          xinit <= LS_WRITE_REG;
          xnext <= LS_CHIRP_STARTK;
        end

        LS_CHIRP_STARTK: begin
          if (ulpi_nxt) begin
            xinit <= LS_CHIRPK;
            adr_q <= 8'hx;
            ulpi_data_out_buf <= 8'h00;
          end else begin
            xinit <= LS_CHIRP_STARTK;
            // todo: chirp = ON
            ulpi_data_out_buf <= 8'h40;
          end
          xnext <= 4'hx;
        end

        LS_CHIRPK: begin
          if (state_counter > CHIRP_K_TIME) begin
            xinit <= LS_STP;
            xnext <= LS_CHIRPKJ;
          end else begin
            xinit <= xinit;
            xnext <= 4'hx;
          end
        end

        LS_CHIRPKJ: begin
          if (chirp_kj_counter > 3 && state_counter > CHIRP_KJ_TIME) begin
            xinit <= LS_WRITE_REG;
            xnext <= LS_IDLE;
          end else begin
            xinit <= xinit;
            xnext <= 4'hx;
          end
        end

        LS_SWITCH_FSSTART: begin
          xinit <= LS_WRITE_REG;
          xnext <= LS_SWITCH_FS;
        end

        LS_SWITCH_FS: begin
          if (state_counter > SWITCH_TIME) begin
            if (LineState == 2'b00 && HIGH_SPEED == 1) begin
              xinit <= LS_CHIRP_START;
            end else begin
              xinit <= LS_IDLE;
            end
          end else begin
            xinit <= xinit;
          end
          xnext <= 4'hx;
        end
      endcase
    end
  end


endmodule  // ulpi_line_state

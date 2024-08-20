`timescale 1ns / 100ps
module ep_bulk_in_tb;


  reg clock = 1;
  reg reset = 0;

  always #5 clock <= ~clock;

  initial begin
    $display("Bulk IN End-Point Testbench:");
    $dumpfile("ep_bulk_in_tb.vcd");
    $dumpvars;

    #400 $finish;
  end

  reg set_conf_q, clr_conf_q;
  reg selected_q;
  reg ack_recv_q, err_recv_q;

  reg svalid, skeep, slast, mready;
  reg [7:0] sdata;
  wire sready, mvalid, mkeep, mlast;
  wire [3:0] muser;
  wire [7:0] mdata;

  reg splurge = 0;

  initial begin
    #40 reset <= 1'b1;
    set_conf_q <= 1'b0;
    clr_conf_q <= 1'b0;
    selected_q <= 1'b0;
    ack_recv_q <= 1'b0;
    err_recv_q <= 1'b0;
    svalid <= 1'b0;
    skeep  <= 1'b0;
    slast  <= 1'b0;
    sdata  <= 'bx;
    mready <= 1'b0;
    #15 reset <= 1'b0;

    #10 if (sready || mvalid) begin
      $error("EP IN driving bus when IDLE");
      $fatal;
    end

    // Not configured, so we expect to see a STALL
    #10 selected_q <= 1'b1;
    #10 selected_q <= 1'b0;
    #10 mready <= 1'b1;
    #10 mready <= 1'b0;

    // -- ENABLE EP IN -- //

    #20 set_conf_q <= 1'b1;
    #10 set_conf_q <= 1'b0;

    // No data, so we expect to see a NAK
    #10 selected_q <= 1'b1;
    #10 selected_q <= 1'b0;
    #10 mready <= 1'b1;
    #10 mready <= 1'b0;


    // Now with data
    #20 send_data(1);
    
    #20 ack_recv_q <= 1'b1;
    #10 ack_recv_q <= 1'b0;
  end


  integer count;

  task send_data;
    input [2:0] len;
    begin
      count  <= len == 0 ? len + 1 : len;
      svalid <= 1'b1;
      skeep  <= len != 3'd0;
      slast  <= len <= 3'd1;
      sdata  <= $urandom;

      @(posedge clock);
      selected_q <= 1'b1;

      while (count > 0) begin
        mready <= ~(mvalid & mlast);

        @(posedge clock);
        selected_q <= 1'b0;
        if (svalid && sready) begin
          svalid <= count > 1;
          slast <= count < 2;
          sdata <= $urandom;
          count <= count - 1;
        end
      end
      svalid <= 1'b0;
      mready <= ~(mvalid & mlast);

      while (mvalid) begin
        @(posedge clock);
        mready <= ~(mvalid & mlast);
      end
      mready <= 1'b0;
      $display("%10t: DATAx packet sent (bytes: %d)", $time, len);
    end
  endtask // send_data


  //
  //  Core Under New Tests
  ///

  ep_bulk_in #(.ENABLED(1), .CONSTANT(1)) EP_IN0
    (
     .clock(clock),
     .reset(reset),

     .set_conf_i(set_conf_q), // From CONTROL PIPE0
     .clr_conf_i(clr_conf_q), // From CONTROL PIPE0
     .selected_i(selected_q), // From USB controller
     .ack_recv_i(ack_recv_q), // From USB decoder
     .err_recv_i(err_recv_q), // From USB decoder

     .s_tvalid(svalid), // From Bulk IN data source
     .s_tready(sready),
     .s_tkeep(skeep),
     .s_tlast(slast),
     .s_tdata(sdata),

     .m_tvalid(mvalid), // To USB encoder
     .m_tready(mready),
     .m_tkeep(mkeep),
     .m_tlast(mlast),
     .m_tuser(muser),
     .m_tdata(mdata)
     );


endmodule // ep_bulk_in_tb

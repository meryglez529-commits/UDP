`timescale 1ns / 1ps

module udp_transport_dual_host_tb;
    localparam [47:0] LOCAL_MAC=48'h02_DB_50_00_00_01;
    localparam [31:0] LOCAL_IP=32'hC0A8_0114;
    localparam [47:0] HOST_MAC=48'h9C69_D31A_4C6D;
    localparam [31:0] HOST_IP=32'hC0A8_010A;
    localparam [15:0] CTRL_PORT=16'd32000;
    localparam [15:0] DATA_PORT=16'd32001;
    localparam integer LEN_W=14;

    reg clk=0; always #4 clk=~clk;
    reg resetn=0, link_ready=0, ctrl_soft_resetn=1;
    wire ctrl_channel_resetn;
    reg [7:0] rx_tdata=0; reg rx_tvalid=0, rx_tlast=0; wire rx_tready;
    wire [7:0] tx_tdata; wire tx_tvalid,tx_tlast; reg tx_tready=1;

    wire ctrl_rx_valid; reg ctrl_rx_ready=0; wire [7:0] ctrl_rx_data;
    wire ctrl_rx_last; wire [10:0] ctrl_rx_len;
    wire data_rx_valid; reg data_rx_ready=0; wire [7:0] data_rx_data;
    wire data_rx_last; wire [LEN_W-1:0] data_rx_len;

    reg data_req_valid=0; wire data_req_ready; reg [LEN_W-1:0] data_req_len=0;
    reg data_tx_valid=0; wire data_tx_ready; reg [7:0] data_tx_data=0;
    reg data_tx_last=0; wire data_status_valid; reg data_status_ready=0;
    wire [2:0] data_status;

    reg [7:0] frame[0:9200];
    reg [7:0] tx_capture[0:9200];
    integer tx_index=0,tx_frame_count=0,tx_last_length=0;
    integer errors=0,i,j,timeout;

    udp_transport_dual_host dut (
        .clk_i(clk),.resetn_i(resetn),.link_ready_i(link_ready),
        .ctrl_soft_resetn_i(ctrl_soft_resetn),.ctrl_channel_resetn_o(ctrl_channel_resetn),
        .rx_axis_tdata_i(rx_tdata),.rx_axis_tvalid_i(rx_tvalid),
        .rx_axis_tready_o(rx_tready),.rx_axis_tlast_i(rx_tlast),
        .tx_axis_tdata_o(tx_tdata),.tx_axis_tvalid_o(tx_tvalid),
        .tx_axis_tready_i(tx_tready),.tx_axis_tlast_o(tx_tlast),
        .ctrl_rx_valid_o(ctrl_rx_valid),.ctrl_rx_ready_i(ctrl_rx_ready),
        .ctrl_rx_data_o(ctrl_rx_data),.ctrl_rx_last_o(ctrl_rx_last),
        .ctrl_rx_len_o(ctrl_rx_len),.ctrl_tx_valid_i(1'b0),.ctrl_tx_ready_o(),
        .ctrl_tx_len_i(11'd0),.ctrl_tx_data_valid_i(1'b0),
        .ctrl_tx_data_ready_o(),.ctrl_tx_data_i(8'd0),.ctrl_tx_data_last_i(1'b0),
        .ctrl_tx_error_o(),.data_rx_valid_o(data_rx_valid),
        .data_rx_ready_i(data_rx_ready),.data_rx_data_o(data_rx_data),
        .data_rx_last_o(data_rx_last),.data_rx_len_o(data_rx_len),
        .data_tx_req_valid_i(data_req_valid),.data_tx_req_ready_o(data_req_ready),
        .data_tx_len_i(data_req_len),.data_tx_valid_i(data_tx_valid),
        .data_tx_ready_o(data_tx_ready),.data_tx_data_i(data_tx_data),
        .data_tx_last_i(data_tx_last),.data_tx_cancel_valid_i(1'b0),
        .data_tx_cancel_ready_o(),.data_tx_status_valid_o(data_status_valid),
        .data_tx_status_ready_i(data_status_ready),.data_tx_status_o(data_status),
        .ctrl_rx_level_o(),.data_rx_level_o(),.tx_busy_o(),
        .last_drop_reason_o(),.rx_frames_seen_o(),.rx_udp_accepted_o(),
        .rx_drop_endpoint_o(),.rx_drop_ipv4_o(),.rx_drop_udp_o(),
        .rx_drop_checksum_o(),.rx_drop_oversize_o(),.rx_drop_fifo_full_o(),
        .tx_accepted_o(),.tx_sent_o(),.tx_input_error_o()
    );

    always @(posedge clk) if (tx_tvalid&&tx_tready) begin
        tx_capture[tx_index]<=tx_tdata;
        if (tx_tlast) begin
            tx_last_length<=tx_index+1; tx_index<=0; tx_frame_count<=tx_frame_count+1;
        end else tx_index<=tx_index+1;
    end

    task fail; input [8*100-1:0] msg; begin $display("FAIL: %0s",msg); errors=errors+1; end endtask
    task set16; input integer idx; input[15:0]v; begin frame[idx]=v[15:8];frame[idx+1]=v[7:0];end endtask
    task set32; input integer idx; input[31:0]v; begin
        frame[idx]=v[31:24];frame[idx+1]=v[23:16];frame[idx+2]=v[15:8];frame[idx+3]=v[7:0];end endtask
    task set48; input integer idx; input[47:0]v; begin
        frame[idx]=v[47:40];frame[idx+1]=v[39:32];frame[idx+2]=v[31:24];
        frame[idx+3]=v[23:16];frame[idx+4]=v[15:8];frame[idx+5]=v[7:0];end endtask

    task ipv4_checksum;
        integer sum,w,k; reg[15:0]c;
        begin frame[24]=0;frame[25]=0;sum=0;
            for(k=14;k<34;k=k+2) sum=sum+((frame[k]<<8)|frame[k+1]);
            while(sum>16'hffff) sum=(sum&16'hffff)+(sum>>16);
            c=~sum;set16(24,c);
        end
    endtask
    task udp_checksum; input integer plen;
        integer sum,w,k,ulen; reg[15:0]c;
        begin ulen=plen+8;frame[40]=0;frame[41]=0;
            sum=HOST_IP[31:16]+HOST_IP[15:0]+LOCAL_IP[31:16]+LOCAL_IP[15:0]+16'h11+ulen;
            for(k=34;k<34+ulen;k=k+2) begin w=frame[k]<<8;if(k+1<34+ulen)w=w|frame[k+1];sum=sum+w;end
            while(sum>16'hffff)sum=(sum&16'hffff)+(sum>>16);
            c=~sum;if(c==0)c=16'hffff;set16(40,c);
        end
    endtask
    task build_udp; input integer plen; input[7:0]seed; input[15:0]port;
        integer k; begin
            set48(0,LOCAL_MAC);set48(6,HOST_MAC);set16(12,16'h0800);
            frame[14]=8'h45;frame[15]=0;set16(16,plen+28);set16(18,16'h1234);
            set16(20,16'h4000);frame[22]=64;frame[23]=8'h11;set16(24,0);
            set32(26,HOST_IP);set32(30,LOCAL_IP);set16(34,port);set16(36,port);
            set16(38,plen+8);set16(40,0);
            for(k=0;k<plen;k=k+1)frame[42+k]=seed+k;
            ipv4_checksum();udp_checksum(plen);
        end
    endtask
    task send_frame; input integer flen; integer k; begin
        for(k=0;k<flen;k=k+1)begin
            @(negedge clk);rx_tvalid=1;rx_tdata=frame[k];rx_tlast=(k==flen-1);
            while(!rx_tready)@(negedge clk);@(posedge clk);
        end
        @(negedge clk);rx_tvalid=0;rx_tlast=0;
    end endtask

    task expect_ctrl; input integer len; input[7:0]seed; integer k; begin
        timeout=0;while(!ctrl_rx_valid&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
        if(!ctrl_rx_valid)fail("CONTROL RX timeout");
        if(ctrl_rx_len!=len)fail("CONTROL RX length");
        for(k=0;k<len;k=k+1)begin
            @(negedge clk);if(ctrl_rx_data!==((seed+k)&8'hff))fail("CONTROL RX data");
            if(ctrl_rx_last!==(k==len-1))fail("CONTROL RX last");ctrl_rx_ready=1;@(posedge clk);
        end @(negedge clk);ctrl_rx_ready=0;
    end endtask
    task expect_data; input integer len; input[7:0]seed; integer k; begin
        timeout=0;while(!data_rx_valid&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
        if(!data_rx_valid)fail("DATA RX timeout");
        if(data_rx_len!=len)fail("DATA RX length");
        for(k=0;k<len;k=k+1)begin
            @(negedge clk);if(data_rx_data!==((seed+k)&8'hff))fail("DATA RX data");
            if(data_rx_last!==(k==len-1))fail("DATA RX last");data_rx_ready=1;@(posedge clk);
        end @(negedge clk);data_rx_ready=0;
    end endtask

    task send_data_tx; input integer len; input[7:0]seed; integer k; begin
        @(negedge clk);data_req_len=len;data_req_valid=1;#1;
        while(!data_req_ready)@(negedge clk);@(posedge clk);@(negedge clk);data_req_valid=0;
        for(k=0;k<len;k=k+1)begin
            data_tx_valid=1;data_tx_data=seed+k;data_tx_last=(k==len-1);#1;
            while(!data_tx_ready)@(negedge clk);@(posedge clk);@(negedge clk);
        end data_tx_valid=0;data_tx_last=0;
        timeout=0;while(!data_status_valid&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
        if(!data_status_valid||data_status!=0)fail("DATA TX commit status");
        data_status_ready=1;@(posedge clk);@(negedge clk);data_status_ready=0;
    end endtask
    task wait_tx; input integer prior; begin
        timeout=0;while((tx_frame_count==prior)&&(timeout<20000))begin @(negedge clk);timeout=timeout+1;end
        if(tx_frame_count==prior)fail("TX frame timeout");
    end endtask

    initial begin
        repeat(6)@(posedge clk);@(negedge clk);resetn=1;link_ready=1;

        build_udp(16,8'h10,CTRL_PORT);send_frame(58);expect_ctrl(16,8'h10);
        build_udp(8172,8'h30,DATA_PORT);send_frame(8214);expect_data(8172,8'h30);

        build_udp(64,8'h70,DATA_PORT);frame[41]=frame[41]^8'h01;send_frame(106);
        repeat(20)@(posedge clk);if(data_rx_valid)fail("bad checksum DATA committed");

        i=tx_frame_count;send_data_tx(8972,8'h90);wait_tx(i);
        if(tx_last_length!=9014)fail("DATA TX frame length");
        if({tx_capture[34],tx_capture[35]}!=DATA_PORT ||
           {tx_capture[36],tx_capture[37]}!=DATA_PORT)fail("DATA TX ports");
        if(tx_capture[42]!=8'h90 || tx_capture[9013]!==((8'h90+8971)&8'hff))
            fail("DATA TX payload boundary");
        if({tx_capture[40],tx_capture[41]}==0)fail("DATA TX checksum disabled");

        ctrl_soft_resetn=0;repeat(40)@(posedge clk);
        if(ctrl_channel_resetn)fail("CONTROL reset did not assert");
        if(!link_ready)fail("CONTROL reset changed shared link");
        ctrl_soft_resetn=1;repeat(5)@(posedge clk);
        if(!ctrl_channel_resetn)fail("CONTROL reset did not recover");

        if(errors==0)$display("RESULT=UDP_TRANSPORT_DUAL_HOST_PASSED");
        else $display("RESULT=UDP_TRANSPORT_DUAL_HOST_FAILED errors=%0d",errors);
        $finish;
    end
endmodule

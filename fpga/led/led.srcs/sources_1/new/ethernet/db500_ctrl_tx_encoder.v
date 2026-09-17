`timescale 1ns / 1ps

// Own a complete 16-byte response copy while transferring it into the UDP TX
// payload ring.  No live window data is referenced after load_fire.
module db500_ctrl_tx_encoder (
    input  wire        clk_i,
    input  wire        resetn_i,

    output wire        load_ready_o,
    input  wire        load_fire_i,
    input  wire        load_is_set_i,
    input  wire        load_error_i,
    input  wire [63:0] load_id_i,
    input  wire [15:0] load_addr_i,
    input  wire [31:0] load_data_i,

    output wire        tx_msg_valid_o,
    input  wire        tx_msg_ready_i,
    output wire [10:0] tx_msg_len_o,
    output wire        tx_msg_data_valid_o,
    input  wire        tx_msg_data_ready_i,
    output wire [7:0]  tx_msg_data_o,
    output wire        tx_msg_data_last_o,
    input  wire        tx_msg_error_i,

    output reg         tx_fault_event_o
);

    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_DESC  = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_FAULT = 2'd3;

    reg [1:0]   state;
    reg [127:0] response_record;
    reg [3:0]   byte_index;

    assign load_ready_o = resetn_i && (state == TX_IDLE) && !tx_msg_error_i;
    assign tx_msg_valid_o = resetn_i && (state == TX_DESC) && !tx_msg_error_i;
    assign tx_msg_len_o = 11'd16;
    assign tx_msg_data_valid_o = resetn_i && (state == TX_DATA) && !tx_msg_error_i;
    assign tx_msg_data_o = response_record[127-(byte_index*8) -: 8];
    assign tx_msg_data_last_o = (state == TX_DATA) && (byte_index == 4'd15);

    always @(posedge clk_i) begin
        if (!resetn_i) begin
            state            <= TX_IDLE;
            response_record  <= 128'd0;
            byte_index       <= 4'd0;
            tx_fault_event_o <= 1'b0;
        end else begin
            tx_fault_event_o <= 1'b0;

            if (tx_msg_error_i) begin
                if (state != TX_FAULT)
                    tx_fault_event_o <= 1'b1;
                state <= TX_FAULT;
            end else begin
                case (state)
                    TX_IDLE: begin
                        if (load_fire_i && load_ready_o) begin
                            response_record <= {
                                load_is_set_i ? 8'h82 : 8'h81,
                                load_error_i  ? 8'h01 : 8'h00,
                                load_id_i,
                                load_addr_i,
                                load_data_i
                            };
                            byte_index <= 4'd0;
                            state      <= TX_DESC;
                        end
                    end

                    TX_DESC: begin
                        if (tx_msg_valid_o && tx_msg_ready_i)
                            state <= TX_DATA;
                    end

                    TX_DATA: begin
                        if (tx_msg_data_valid_o && tx_msg_data_ready_i) begin
                            if (byte_index == 4'd15) begin
                                byte_index <= 4'd0;
                                state      <= TX_IDLE;
                            end else begin
                                byte_index <= byte_index + 1'b1;
                            end
                        end
                    end

                    TX_FAULT: state <= TX_FAULT;
                    default: state <= TX_IDLE;
                endcase
            end
        end
    end

endmodule

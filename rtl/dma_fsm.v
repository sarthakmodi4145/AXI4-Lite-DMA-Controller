module dma_fsm(
    input clk,
    input reset,
    input [31:0] control,
    output reg [2:0] state,
    input status
);
reg [2:0] nextstate;
parameter idle=3'b000, fetch=3'b001, transfer=3'b010, done=3'b011, transfer2=3'b100;


reg control0_d;
wire start_pulse = control[0] & ~control0_d;

always@(posedge clk)begin
    if(reset)begin
        state<=idle;
        control0_d<=1'b0;
    end
    else begin
        state<=nextstate;
        control0_d<=control[0];
    end
end
always@(*)begin
    case(state)
        idle:begin
            if(start_pulse)begin
               nextstate=fetch;
            end
            else begin
                nextstate=idle;
            end
        end
        fetch:begin
            nextstate=transfer;
        end
        transfer:begin
            nextstate=transfer2;
        end
        transfer2:begin
            if(status)begin
                nextstate=done;
            end
            else begin
                nextstate=transfer;
            end
        end
        done:begin
            nextstate=idle;
        end
        default: nextstate=idle;
    endcase
end
endmodule

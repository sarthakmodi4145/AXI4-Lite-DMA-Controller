module dma_fsm(
    input clk,
    input reset,

    input [31:0] control,
    output reg [2:0] state,

    input status
);

reg [31:0] i=32'b0;

reg [2:0] nextstate;
parameter idle=000,fetch=001,transfer=010,done=011,transfer2=100;


always@(posedge clk)begin
    if(reset)begin
        state<=idle;
    end
    else begin
        state<=nextstate;
    end
end

always@(*)begin
    case(state)
        idle:begin
            if(control[0]==1)begin
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
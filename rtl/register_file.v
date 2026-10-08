module register_file(
    input clk,
    input reset,
    input wire wr_en,
    input wire[4:0] wr_addr,
    input wire[31:0] wr_data,
    input wire rd_en,
    input wire [4:0] rd_addr,
    output reg [31:0] rd_data,
    input wire dma_done,
    input wire dma_busy,
    output reg[31:0] src_addr,
    output reg[31:0] dest_addr,
    output reg[31:0] length,
    output reg[31:0] control,
    output reg[31:0] status
);
always@(*)begin
    rd_data=32'b0;
    if(rd_en)begin
        if(rd_addr==5'h00)begin
           rd_data=src_addr;
        end
        else if(rd_addr==5'h04)begin
           rd_data=dest_addr;
        end
        else if(rd_addr==5'h08)begin
            rd_data=length;
        end
        else if(rd_addr==5'h0c)begin
            rd_data=control;
        end
        else if(rd_addr == 5'h10)
            rd_data = status;
    end
end
always@(posedge clk) begin
    if(reset)begin
        src_addr<=32'b0;
        dest_addr<=32'b0;
        length<=32'b0;
        control<=32'b0;
        status<=32'b0;
    end
    else begin
        if(wr_en)begin
            if(wr_addr==5'h00)begin
            src_addr<=wr_data;
            end
            else if(wr_addr==5'h04)begin
            dest_addr<=wr_data;
            end
            else if(wr_addr==5'h08)begin
            length<=wr_data;
            end
            else if(wr_addr==5'h0c)begin
            control<=wr_data;
            end
        end
        if(dma_done)begin
            status<=32'b01;
        end
        else if(dma_busy)begin
            status<=32'b10;
        end
        else
            status<=32'b00;
    end
end
endmodule

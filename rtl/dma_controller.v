module dma_controller(
    input clk,
    input reset,
    input [31:0] src_addr,
    input [31:0] dest_addr,
    input [31:0] length,
    input [31:0] control,
    output reg dma_done,
    output reg dma_busy,
    input [31:0] mem_rd_data,
    output reg [31:0] mem_wr_data,
    output reg [31:0] mem_rd_addr,
    output reg [31:0] mem_wr_addr,
    output reg mem_wr_en,
    input [2:0] state,
    output reg status
);
reg [31:0] crr_src_addr;
reg [31:0] crr_dest_addr;
reg [31:0] crr_length;
parameter idle=3'b000, fetch=3'b001, transfer=3'b010, done=3'b011, transfer2=3'b100;
always@(posedge clk) begin
    if(reset)begin
        dma_done<=1'b0;
        dma_busy<=1'b0;
        mem_wr_data<=32'b0;
        mem_wr_addr<=32'b0;
        mem_rd_addr<=32'b0;
        crr_length<=32'b0;
        crr_src_addr<=32'b0;
        crr_dest_addr<=32'b0;
        mem_wr_en<=1'b0;
        status<=1'b0;
    end
    else begin
            if(state==fetch)begin
                dma_busy<=1'b1;
                dma_done<=1'b0;
                crr_src_addr<=src_addr;
                crr_dest_addr<=dest_addr;
                crr_length<=length;
                status<=1'b0;
                mem_wr_en<=1'b0;
            end
            else if(state==transfer)begin
                mem_wr_en<=1'b1;
                mem_rd_addr<=crr_src_addr;
                mem_wr_addr<=crr_dest_addr;
                crr_length<=crr_length-1;
            end
            else if(state==transfer2)begin
                crr_src_addr<=crr_src_addr+1;
                crr_dest_addr<=crr_dest_addr+1;
                mem_wr_data<=mem_rd_data;
                if(crr_length==1)begin
                    status<=1'b1;
                end
            end
            else if(state==done)begin
                dma_busy<=1'b0;
                dma_done<=1'b1;
                mem_wr_en<=1'b0;
            end
    end
end
endmodule

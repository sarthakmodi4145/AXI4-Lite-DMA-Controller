module memory_model(
    input clk,
    input wr_en,
    input [31:0] wr_addr,
    input [31:0] rd_addr,
    input [31:0] wr_data,
    output reg [31:0] rd_data
);
reg [31:0] mem [0:255];
always@(*)begin
    rd_data=mem[rd_addr];
end
always@(posedge clk) begin
    if(wr_en)
        mem[wr_addr]<=wr_data;
end
endmodule

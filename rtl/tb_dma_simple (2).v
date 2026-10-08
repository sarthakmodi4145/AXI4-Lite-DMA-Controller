`timescale 1ns/1ps



module tb_dma_simple;

localparam REG_SRC    = 32'h00;
localparam REG_DEST   = 32'h04;
localparam REG_LEN    = 32'h08;
localparam REG_CTRL   = 32'h0C;
localparam REG_STATUS = 32'h10;

localparam SRC_BASE  = 32'd0;
localparam DEST_BASE = 32'd32;
localparam XFER_LEN  = 32'd8;   // keep it small so it's easy to trace

reg clk = 0;
reg reset;

reg  [31:0] awaddr, wdata, araddr;
reg         awvalid, wvalid, bready, arvalid, rready;
wire        awready, wready, bvalid, arready, rvalid;
wire [1:0]  bresp, rresp;
wire [31:0] rdata;
wire        irq_dma_done;

integer i, errors;
reg [31:0] status_rd, rd_val;

always #5 clk = ~clk;   // 100 MHz

axi_dma_top dut (
    .clk(clk), .reset(reset),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata),   .s_axi_wstrb(4'hF),       .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp),   .s_axi_bvalid(bvalid),    .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),  .s_axi_arready(arready),
    .s_axi_rdata(rdata),   .s_axi_rresp(rresp),      .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .irq_dma_done(irq_dma_done)
);


task axi_write(input [31:0] addr, input [31:0] data);
    reg aw_done, w_done;
    begin
        aw_done = 0; w_done = 0;
        awaddr = addr; awvalid = 1;
        wdata  = data; wvalid  = 1;
        bready = 1;

        while (!(aw_done && w_done)) begin
            @(posedge clk);
            if (!aw_done && awready) begin
                awvalid = 0;
                aw_done = 1;
            end
            if (!w_done && wready) begin
                wvalid = 0;
                w_done = 1;
            end
        end

        while (!bvalid) @(posedge clk);
        @(posedge clk);
        bready = 0;
    end
endtask

// ---- read one register over AXI4-Lite ----
task axi_read(input [31:0] addr, output [31:0] data);
    begin
        araddr = addr; arvalid = 1; rready = 1;
        while (!arready) @(posedge clk);
        @(posedge clk);
        arvalid = 0;
        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk);
        rready = 0;
    end
endtask

initial begin
    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
    reset = 1;
    errors = 0;
    repeat (3) @(posedge clk);
    reset = 0;
    repeat (2) @(posedge clk);

    // fill source words with a known pattern, clear the destination
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        dut.u_memory_model.mem[SRC_BASE  + i] = 32'hA000_0000 + i;
        dut.u_memory_model.mem[DEST_BASE + i] = 32'h0;
    end

    // program the DMA and kick it off
    axi_write(REG_SRC,  SRC_BASE);
    axi_write(REG_DEST, DEST_BASE);
    axi_write(REG_LEN,  XFER_LEN);
    axi_write(REG_CTRL, 32'h1);        // bit0 = start

    $display("[%0t] DMA started: src=%0d dest=%0d len=%0d", $time, SRC_BASE, DEST_BASE, XFER_LEN);

    // poll status until it reads back "done" (32'h1)
    status_rd = 0; i = 0;
    while (status_rd != 32'h1 && i < 500) begin
        axi_read(REG_STATUS, status_rd);
        i = i + 1;
    end
    if (status_rd != 32'h1) begin
        $display("[%0t] ERROR: DMA never finished, status=%0h", $time, status_rd);
        errors = errors + 1;
    end else begin
        $display("[%0t] DMA done, polled status %0d time(s)", $time, i);
    end

    axi_write(REG_CTRL, 32'h0);        // clear start bit
    repeat (3) @(posedge clk);

    // check every word landed correctly
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        if (dut.u_memory_model.mem[DEST_BASE + i] !== dut.u_memory_model.mem[SRC_BASE + i]) begin
            $display("[%0t] MISMATCH idx=%0d src=%h dest=%h", $time, i,
                       dut.u_memory_model.mem[SRC_BASE + i], dut.u_memory_model.mem[DEST_BASE + i]);
            errors = errors + 1;
        end
    end

    // one extra sanity check: read back a config register
    axi_read(REG_LEN, rd_val);
    if (rd_val !== XFER_LEN) begin
        $display("[%0t] ERROR: LENGTH readback = %0d, expected %0d", $time, rd_val, XFER_LEN);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("TEST PASSED");
    else
        $display("TEST FAILED: %0d error(s)", errors);

    $finish;
end

initial begin
    #50000;
    $display("[%0t] ERROR: simulation timeout", $time);
    $finish;
end

endmodule

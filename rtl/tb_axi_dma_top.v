`timescale 1ns/1ps

module tb_axi_dma_top;

localparam ADDR_WIDTH = 32;
localparam DATA_WIDTH = 32;

// Register offsets (must match axi_lite_slave / register_file map)
localparam REG_SRC_ADDR  = 32'h00;
localparam REG_DEST_ADDR = 32'h04;
localparam REG_LENGTH    = 32'h08;
localparam REG_CONTROL   = 32'h0C;
localparam REG_STATUS    = 32'h10;

localparam SRC_BASE  = 32'd0;
localparam DEST_BASE = 32'd64;
localparam XFER_LEN  = 32'd16;

reg clk;
reg reset;

// AXI4-Lite interconnect wires between master model and DUT
wire [ADDR_WIDTH-1:0] awaddr;
wire                  awvalid;
wire                  awready;
wire [DATA_WIDTH-1:0] wdata;
wire [(DATA_WIDTH/8)-1:0] wstrb;
wire                  wvalid;
wire                  wready;
wire [1:0]            bresp;
wire                  bvalid;
wire                  bready;
wire [ADDR_WIDTH-1:0] araddr;
wire                  arvalid;
wire                  arready;
wire [DATA_WIDTH-1:0] rdata;
wire [1:0]            rresp;
wire                  rvalid;
wire                  rready;
wire                  irq_dma_done;

integer i;
integer errors;
reg [31:0] read_status;
reg [31:0] read_val;

// ---------------- Clock generation ----------------
initial clk = 1'b0;
always #5 clk = ~clk; // 100 MHz

// ---------------- DUT ----------------
axi_dma_top #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) dut (
    .clk           (clk),
    .reset         (reset),

    .s_axi_awaddr  (awaddr),
    .s_axi_awvalid (awvalid),
    .s_axi_awready (awready),

    .s_axi_wdata   (wdata),
    .s_axi_wstrb   (wstrb),
    .s_axi_wvalid  (wvalid),
    .s_axi_wready  (wready),

    .s_axi_bresp   (bresp),
    .s_axi_bvalid  (bvalid),
    .s_axi_bready  (bready),

    .s_axi_araddr  (araddr),
    .s_axi_arvalid (arvalid),
    .s_axi_arready (arready),

    .s_axi_rdata   (rdata),
    .s_axi_rresp   (rresp),
    .s_axi_rvalid  (rvalid),
    .s_axi_rready  (rready),

    .irq_dma_done  (irq_dma_done)
);

// ---------------- AXI4-Lite master BFM ----------------
axi_master_model #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) master (
    .clk           (clk),
    .reset         (reset),

    .m_axi_awaddr  (awaddr),
    .m_axi_awvalid (awvalid),
    .m_axi_awready (awready),

    .m_axi_wdata   (wdata),
    .m_axi_wstrb   (wstrb),
    .m_axi_wvalid  (wvalid),
    .m_axi_wready  (wready),

    .m_axi_bresp   (bresp),
    .m_axi_bvalid  (bvalid),
    .m_axi_bready  (bready),

    .m_axi_araddr  (araddr),
    .m_axi_arvalid (arvalid),
    .m_axi_arready (arready),

    .m_axi_rdata   (rdata),
    .m_axi_rresp   (rresp),
    .m_axi_rvalid  (rvalid),
    .m_axi_rready  (rready)
);

// ---------------- Stimulus ----------------
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_axi_dma_top);
    reset  = 1'b1;
    errors = 0;

    repeat (5) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    // Preload source memory region with a known pattern, directly via
    // hierarchical reference into the memory model (simulation-only trick;
    // on real hardware this would come from a real bus master/DMA source).
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        dut.u_memory_model.mem[SRC_BASE + i] = 32'hA000_0000 + i;
    end
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        dut.u_memory_model.mem[DEST_BASE + i] = 32'h0;
    end

    // Program the DMA registers over AXI4-Lite
    master.axi_write(REG_SRC_ADDR,  SRC_BASE);
    master.axi_write(REG_DEST_ADDR, DEST_BASE);
    master.axi_write(REG_LENGTH,    XFER_LEN);
    master.axi_write(REG_CONTROL,   32'h0000_0001); // bit0 = start

    $display("[%0t] DMA configured: src=%0d dest=%0d len=%0d",
              $time, SRC_BASE, DEST_BASE, XFER_LEN);

    // Poll status register until dma_done (status == 32'h1)
    read_status = 32'h0;
    i = 0;
    while (read_status != 32'h1 && i < 1000) begin
        master.axi_read(REG_STATUS, read_status);
        i = i + 1;
        repeat (2) @(posedge clk);
    end

    if (read_status != 32'h1) begin
        $display("[%0t] ERROR: DMA did not complete (timed out), status=%0h",
                  $time, read_status);
        errors = errors + 1;
    end else begin
        $display("[%0t] DMA reported done after %0d polls", $time, i);
    end

    // Clear the control 'start' bit so the FSM doesn't immediately
    // re-trigger (control[0] stays latched otherwise).
    master.axi_write(REG_CONTROL, 32'h0000_0000);
    repeat (5) @(posedge clk);

    // Check destination memory against source
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        if (dut.u_memory_model.mem[DEST_BASE + i] !== dut.u_memory_model.mem[SRC_BASE + i]) begin
            $display("[%0t] MISMATCH at idx %0d: src=%h dest=%h",
                      $time, i,
                      dut.u_memory_model.mem[SRC_BASE + i],
                      dut.u_memory_model.mem[DEST_BASE + i]);
            errors = errors + 1;
        end
    end

    // Also sanity-check via an AXI read-back of one config register
    master.axi_read(REG_LENGTH, read_val);
    if (read_val !== XFER_LEN) begin
        $display("[%0t] ERROR: LENGTH register readback mismatch: got %0d expected %0d",
                  $time, read_val, XFER_LEN);
        errors = errors + 1;
    end

    if (errors == 0) begin
        $display("[%0t] Transfer 1 (len=%0d) PASSED", $time, XFER_LEN);
    end else begin
        $display("[%0t] Transfer 1 (len=%0d) FAILED (%0d errors)", $time, XFER_LEN, errors);
    end

   
    begin : second_transfer
        integer errors2;
        reg [31:0] status2;
        integer j;
        localparam SRC2  = 32'd100;
        localparam DEST2 = 32'd150;
        localparam LEN2  = 32'd1;

        errors2 = 0;

        dut.u_memory_model.mem[SRC2]  = 32'hDEAD_BEEF;
        dut.u_memory_model.mem[DEST2] = 32'h0;

        master.axi_write(REG_SRC_ADDR,  SRC2);
        master.axi_write(REG_DEST_ADDR, DEST2);
        master.axi_write(REG_LENGTH,    LEN2);
        master.axi_write(REG_CONTROL,   32'h0000_0001);

        status2 = 32'h0;
        j = 0;
        while (status2 != 32'h1 && j < 1000) begin
            master.axi_read(REG_STATUS, status2);
            j = j + 1;
            repeat (2) @(posedge clk);
        end

        if (status2 != 32'h1) begin
            $display("[%0t] ERROR: Transfer 2 did not complete (timeout)", $time);
            errors2 = errors2 + 1;
        end

        master.axi_write(REG_CONTROL, 32'h0000_0000);
        repeat (5) @(posedge clk);

        if (dut.u_memory_model.mem[DEST2] !== dut.u_memory_model.mem[SRC2]) begin
            $display("[%0t] MISMATCH: src2=%h dest2=%h",
                      $time, dut.u_memory_model.mem[SRC2], dut.u_memory_model.mem[DEST2]);
            errors2 = errors2 + 1;
        end

        if (errors2 == 0) begin
            $display("[%0t] Transfer 2 (len=%0d, single word) PASSED", $time, LEN2);
        end else begin
            $display("[%0t] Transfer 2 (len=%0d) FAILED (%0d errors)", $time, LEN2, errors2);
        end
        errors = errors + errors2;
    end

    if (errors == 0) begin
        $display("=====================================");
        $display(" ALL TESTS PASSED");
        $display("=====================================");
    end else begin
        $display("=====================================");
        $display(" TEST FAILED: %0d total error(s) found", errors);
        $display("=====================================");
    end

    $finish;
end


initial begin
    #200000;
    $display("[%0t] ERROR: simulation timeout", $time);
    $finish;
end

endmodule

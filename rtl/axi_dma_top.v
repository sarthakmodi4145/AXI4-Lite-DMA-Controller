// axi_dma_top.v
// Top-level DMA subsystem. Exposes a single AXI4-Lite slave port used by a
// host/CPU to configure the DMA (src_addr, dest_addr, length, control) and
// poll status. Internally wires together:
//   axi_lite_slave -> register_file -> dma_fsm -> dma_controller -> memory_model

module axi_dma_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input                        clk,
    input                        reset,

    // ---------------- AXI4-Lite slave (configuration port) ----------------
    input      [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input                        s_axi_awvalid,
    output                       s_axi_awready,

    input      [DATA_WIDTH-1:0]  s_axi_wdata,
    input      [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input                        s_axi_wvalid,
    output                       s_axi_wready,

    output     [1:0]             s_axi_bresp,
    output                       s_axi_bvalid,
    input                        s_axi_bready,

    input      [ADDR_WIDTH-1:0]  s_axi_araddr,
    input                        s_axi_arvalid,
    output                       s_axi_arready,

    output     [DATA_WIDTH-1:0]  s_axi_rdata,
    output     [1:0]             s_axi_rresp,
    output                       s_axi_rvalid,
    input                        s_axi_rready,

    // ---------------- Status / interrupt style outputs ----------------
    output                       irq_dma_done
);

// ---------------- internal wires ----------------

// axi_lite_slave <-> register_file
wire        rf_wr_en;
wire [4:0]  rf_wr_addr;
wire [31:0] rf_wr_data;
wire        rf_rd_en;
wire [4:0]  rf_rd_addr;
wire [31:0] rf_rd_data;

// register_file <-> dma_fsm / dma_controller
wire [31:0] cfg_src_addr;
wire [31:0] cfg_dest_addr;
wire [31:0] cfg_length;
wire [31:0] cfg_control;

// dma_controller <-> register_file (status)
wire        dma_done;
wire        dma_busy;

// dma_fsm <-> dma_controller
wire [2:0]  fsm_state;
wire        xfer_status;

// dma_controller <-> memory_model
wire [31:0] mem_rd_data;
wire [31:0] mem_wr_data;
wire [31:0] mem_rd_addr;
wire [31:0] mem_wr_addr;
wire        mem_wr_en;

assign irq_dma_done = dma_done;

// ---------------- AXI4-Lite slave ----------------
axi_lite_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_axi_lite_slave (
    .clk           (clk),
    .reset         (reset),

    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),

    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),

    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),

    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),

    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),

    .wr_en         (rf_wr_en),
    .wr_addr       (rf_wr_addr),
    .wr_data       (rf_wr_data),
    .rd_en         (rf_rd_en),
    .rd_addr       (rf_rd_addr),
    .rd_data       (rf_rd_data)
);

// ---------------- Register file ----------------
register_file u_register_file (
    .clk       (clk),
    .reset     (reset),

    .wr_en     (rf_wr_en),
    .wr_addr   (rf_wr_addr),
    .wr_data   (rf_wr_data),
    .rd_en     (rf_rd_en),
    .rd_addr   (rf_rd_addr),
    .rd_data   (rf_rd_data),

    .dma_done  (dma_done),
    .dma_busy  (dma_busy),

    .src_addr  (cfg_src_addr),
    .dest_addr (cfg_dest_addr),
    .length    (cfg_length),
    .control   (cfg_control),
    .status    () // 32-bit status readable via AXI at offset 0x10; unused internally
);

// ---------------- DMA FSM ----------------
dma_fsm u_dma_fsm (
    .clk     (clk),
    .reset   (reset),
    .control (cfg_control),
    .state   (fsm_state),
    .status  (xfer_status)
);

// ---------------- DMA controller (datapath) ----------------
dma_controller u_dma_controller (
    .clk         (clk),
    .reset       (reset),

    .src_addr    (cfg_src_addr),
    .dest_addr   (cfg_dest_addr),
    .length      (cfg_length),
    .control     (cfg_control),

    .dma_done    (dma_done),
    .dma_busy    (dma_busy),

    .mem_rd_data (mem_rd_data),
    .mem_wr_data (mem_wr_data),
    .mem_rd_addr (mem_rd_addr),
    .mem_wr_addr (mem_wr_addr),
    .mem_wr_en   (mem_wr_en),

    .state       (fsm_state),
    .status      (xfer_status)
);

// ---------------- Memory model ----------------
memory_model u_memory_model (
    .clk      (clk),
    .wr_en    (mem_wr_en),
    .wr_addr  (mem_wr_addr),
    .rd_addr  (mem_rd_addr),
    .wr_data  (mem_wr_data),
    .rd_data  (mem_rd_data)
);

endmodule

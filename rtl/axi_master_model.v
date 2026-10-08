// axi_master_model.v
// Simple behavioral AXI4-Lite master (bus functional model) intended for
// testbench use. Exposes axi_write() / axi_read() tasks that a testbench
// can call (hierarchically) to drive an AXI4-Lite slave, e.g. axi_lite_slave.

module axi_master_model #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input                         clk,
    input                         reset,

    // Write address channel
    output reg [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output reg                    m_axi_awvalid,
    input                         m_axi_awready,

    // Write data channel
    output reg [DATA_WIDTH-1:0]   m_axi_wdata,
    output reg [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output reg                    m_axi_wvalid,
    input                         m_axi_wready,

    // Write response channel
    input      [1:0]              m_axi_bresp,
    input                         m_axi_bvalid,
    output reg                    m_axi_bready,

    // Read address channel
    output reg [ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg                    m_axi_arvalid,
    input                         m_axi_arready,

    // Read data channel
    input      [DATA_WIDTH-1:0]   m_axi_rdata,
    input      [1:0]              m_axi_rresp,
    input                         m_axi_rvalid,
    output reg                    m_axi_rready
);

initial begin
    m_axi_awaddr  = {ADDR_WIDTH{1'b0}};
    m_axi_awvalid = 1'b0;
    m_axi_wdata   = {DATA_WIDTH{1'b0}};
    m_axi_wstrb   = {(DATA_WIDTH/8){1'b1}};
    m_axi_wvalid  = 1'b0;
    m_axi_bready  = 1'b0;
    m_axi_araddr  = {ADDR_WIDTH{1'b0}};
    m_axi_arvalid = 1'b0;
    m_axi_rready  = 1'b0;
end

// ------------------------------------------------------------------
// axi_write: performs one AXI4-Lite write transaction.
// Holds AWVALID/WVALID/data stable until each is accepted, then waits
// for BVALID before completing, exactly as the protocol requires.
// ------------------------------------------------------------------
task axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
    reg aw_accepted;
    reg w_accepted;
    begin
        aw_accepted = 1'b0;
        w_accepted  = 1'b0;

        m_axi_awaddr  = addr;
        m_axi_awvalid = 1'b1;
        m_axi_wdata   = data;
        m_axi_wstrb   = {(DATA_WIDTH/8){1'b1}};
        m_axi_wvalid  = 1'b1;
        m_axi_bready  = 1'b1;

        // Wait until both address and data have been accepted
        while (!(aw_accepted && w_accepted)) begin
            @(posedge clk);
            if (!aw_accepted && m_axi_awready) begin
                aw_accepted = 1'b1;
            end
            if (!w_accepted && m_axi_wready) begin
                w_accepted = 1'b1;
            end
        end

        m_axi_awvalid = 1'b0;
        m_axi_wvalid  = 1'b0;

        // Wait for the write response
        while (!m_axi_bvalid) begin
            @(posedge clk);
        end
        @(posedge clk);
        m_axi_bready = 1'b0;
    end
endtask

// ------------------------------------------------------------------
// axi_read: performs one AXI4-Lite read transaction, returns data.
// ------------------------------------------------------------------
task axi_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
    begin
        m_axi_araddr  = addr;
        m_axi_arvalid = 1'b1;
        m_axi_rready  = 1'b1;

        while (!m_axi_arready) begin
            @(posedge clk);
        end
        @(posedge clk);
        m_axi_arvalid = 1'b0;

        while (!m_axi_rvalid) begin
            @(posedge clk);
        end
        data = m_axi_rdata;
        @(posedge clk);
        m_axi_rready = 1'b0;
    end
endtask

endmodule

// axi_lite_slave.v
// AXI4-Lite slave bridge. Converts the AXI4-Lite write/read channel
// handshaking into the simple synchronous register interface expected
// by register_file (wr_en/wr_addr/wr_data, rd_en/rd_addr/rd_data).
//
// Address map (byte addresses on AXI bus, matching register_file's decode):
//   0x00 : src_addr
//   0x04 : dest_addr
//   0x08 : length
//   0x0C : control
//   0x10 : status  (read-only)
// NOTE: register_file compares wr_addr/rd_addr directly against these raw
// byte-address values (5'h00, 5'h04, ...), so this bridge passes the low
// address bits straight through rather than converting to a word index.

module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input                        clk,
    input                        reset,

    // ---------------- AXI4-Lite write address channel ----------------
    input      [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input                        s_axi_awvalid,
    output reg                   s_axi_awready,

    // ---------------- AXI4-Lite write data channel --------------------
    input      [DATA_WIDTH-1:0]  s_axi_wdata,
    input      [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input                        s_axi_wvalid,
    output reg                   s_axi_wready,

    // ---------------- AXI4-Lite write response channel -----------------
    output reg [1:0]             s_axi_bresp,
    output reg                   s_axi_bvalid,
    input                        s_axi_bready,

    // ---------------- AXI4-Lite read address channel -------------------
    input      [ADDR_WIDTH-1:0]  s_axi_araddr,
    input                        s_axi_arvalid,
    output reg                   s_axi_arready,

    // ---------------- AXI4-Lite read data channel -----------------------
    output reg [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg [1:0]             s_axi_rresp,
    output reg                   s_axi_rvalid,
    input                        s_axi_rready,

    // ---------------- Simple register-file side interface --------------
    output reg                   wr_en,
    output reg [4:0]             wr_addr,
    output reg [31:0]            wr_data,
    output reg                   rd_en,
    output reg [4:0]             rd_addr,
    input      [31:0]            rd_data
);

localparam RESP_OKAY = 2'b00;

// Latched write address/data, used so AW and W can arrive in any order
// and so the values are still available at commit time even if the
// master deasserts WVALID/WDATA right after the WREADY handshake.
reg [ADDR_WIDTH-1:0] awaddr_latch;
reg [DATA_WIDTH-1:0] wdata_latch;
reg                  aw_done;
reg                  w_done;

// ---------------------------------------------------------------
// Write channel FSM
// ---------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= RESP_OKAY;
        aw_done       <= 1'b0;
        w_done        <= 1'b0;
        awaddr_latch  <= {ADDR_WIDTH{1'b0}};
        wdata_latch   <= {DATA_WIDTH{1'b0}};
        wr_en         <= 1'b0;
        wr_addr       <= 5'b0;
        wr_data       <= 32'b0;
    end else begin
        wr_en <= 1'b0; // default: pulse for one cycle only

        // Accept write address
        if (!aw_done && s_axi_awvalid && !s_axi_bvalid) begin
            s_axi_awready <= 1'b1;
            awaddr_latch  <= s_axi_awaddr;
            aw_done       <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
        end

        // Accept write data
        if (!w_done && s_axi_wvalid && !s_axi_bvalid) begin
            s_axi_wready <= 1'b1;
            wdata_latch  <= s_axi_wdata;
            w_done       <= 1'b1;
        end else begin
            s_axi_wready <= 1'b0;
        end

        // Once both address and data have been captured, commit to
        // register_file and raise the write response.
        if (aw_done && w_done && !s_axi_bvalid) begin
            wr_en        <= 1'b1;
            // register_file decodes on raw byte address (5'h00/04/08/0c/10),
            // not a word index, so pass the low address bits through as-is.
            wr_addr      <= awaddr_latch[4:0];
            wr_data      <= wdata_latch;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= RESP_OKAY;
            aw_done      <= 1'b0;
            w_done       <= 1'b0;
        end

        // Clear response once master accepts it
        if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------
// Read channel FSM
// ---------------------------------------------------------------
reg ar_done;

always @(posedge clk) begin
    if (reset) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= RESP_OKAY;
        s_axi_rdata   <= 32'b0;
        ar_done       <= 1'b0;
        rd_en         <= 1'b0;
        rd_addr       <= 5'b0;
    end else begin
        rd_en <= 1'b0;

        if (!ar_done && s_axi_arvalid && !s_axi_rvalid) begin
            s_axi_arready <= 1'b1;
            // Same byte-address decode as the write side.
            rd_addr       <= s_axi_araddr[4:0];
            rd_en         <= 1'b1;
            ar_done       <= 1'b1;
        end else begin
            s_axi_arready <= 1'b0;
        end

        // rd_data from register_file is combinational off rd_addr/rd_en,
        // so it is valid the cycle after we assert rd_en/rd_addr.
        if (ar_done && !s_axi_rvalid) begin
            s_axi_rdata  <= rd_data;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rvalid <= 1'b1;
            ar_done      <= 1'b0;
        end

        if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule

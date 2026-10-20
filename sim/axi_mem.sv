// An AXI4 memory for the testbench, 64-bit data. It takes one read and one
// write at a time, as the harness does, and delays every ready and every
// response by a pseudo-random number of cycles. Each transfer is logged, and
// one the harness does not expect is marked (see `odd`).
module axi_mem #(
    parameter string NAME = "mem",
    parameter int    AW   = 32,
    parameter int    IW   = 6,
    parameter int    SEED = 16'hace1
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          awvalid, output logic awready,
    input  logic [IW-1:0] awid,    input  logic [AW-1:0] awaddr,
    input  logic [7:0]    awlen,   input  logic [2:0] awsize, input logic [1:0] awburst,
    input  logic          awlock,
    input  logic          wvalid,  output logic wready,
    input  logic [63:0]   wdata,   input  logic [7:0] wstrb, input logic wlast,
    output logic          bvalid,  input  logic bready,
    output logic [IW-1:0] bid,
    input  logic          arvalid, output logic arready,
    input  logic [IW-1:0] arid,    input  logic [AW-1:0] araddr,
    input  logic [7:0]    arlen,   input  logic [2:0] arsize, input logic [1:0] arburst,
    input  logic          arlock,
    output logic          rvalid,  input  logic rready,
    output logic [IW-1:0] rid,     output logic [63:0] rdata, output logic rlast
);
    logic [63:0] words [longint];   // by byte address >> 3
    longint unsigned cycle = 0;
    longint unsigned last_move = 0;
    int writes = 0, reads = 0, odds = 0;

    logic [15:0] lfsr = SEED[15:0];
    always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

    function automatic logic [63:0] peek(longint unsigned addr);
        return words.exists(addr >> 3) ? words[addr >> 3] : 64'h0;
    endfunction
    function automatic void poke(longint unsigned addr, logic [63:0] data, logic [7:0] strb);
        logic [63:0] w = peek(addr);
        for (int i = 0; i < 8; i++) if (strb[i]) w[i*8 +: 8] = data[i*8 +: 8];
        words[addr >> 3] = w;
    endfunction

    // What the harness's DRAM path does not take: anything but INCR, a
    // locked transfer, a burst narrower than the bus, one that crosses 4 KB.
    function automatic string odd(longint unsigned addr, logic [7:0] len, logic [2:0] size,
                                  logic [1:0] burst, logic lock);
        longint unsigned last = addr + (longint'(len) << size);
        string s;
        s = "";
        if (burst != 2'd1) s = {s, " burst!=INCR"};
        if (lock) s = {s, " lock"};
        if (size != 3'd3 && len != 8'd0) s = {s, " narrow-burst"};
        if ((addr >> 12) != (last >> 12)) s = {s, " crosses-4K"};
        return s;
    endfunction

    // --- write ---
    logic        w_busy, w_have, b_wait_on;
    logic [AW-1:0] w_addr; logic [7:0] w_left; logic [2:0] w_size; logic [IW-1:0] w_id;
    logic [3:0]  b_wait;
    assign awready = rst_n && !w_busy && lfsr[0];
    assign wready  = rst_n && w_busy && w_have && lfsr[1];
    assign bvalid  = b_wait_on && b_wait == 0;
    assign bid     = w_id;

    // --- read ---
    logic        r_busy;
    logic [AW-1:0] r_addr; logic [7:0] r_left; logic [2:0] r_size; logic [IW-1:0] r_id;
    logic [3:0]  r_wait;
    assign arready = rst_n && !r_busy && lfsr[2];
    assign rvalid  = r_busy && r_wait == 0;
    assign rid     = r_id;
    assign rdata   = peek(r_addr);
    assign rlast   = r_left == 0;

    string o;
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!rst_n) begin
            w_busy <= 0; w_have <= 0; b_wait_on <= 0; r_busy <= 0;
        end else begin
            if (awvalid && awready) begin
                o = odd(awaddr, awlen, awsize, awburst, awlock);
                w_busy <= 1; w_have <= 1;
                w_addr <= awaddr; w_left <= awlen; w_size <= awsize; w_id <= awid;
                writes <= writes + 1;
                $display("%0d %s AW id=%0d addr=%h len=%0d size=%0d burst=%0d%s", cycle, NAME, awid, awaddr,
                         awlen, awsize, awburst, o);
                if (o != "") odds <= odds + 1;
                last_move <= cycle;
            end
            if (wvalid && wready) begin
                poke(w_addr, wdata, wstrb);
                if (w_left == 0) begin
                    if (!wlast) $display("%0d %s W: wlast missing", cycle, NAME);
                    w_have <= 0; b_wait_on <= 1; b_wait <= lfsr[6:3];
                end else begin
                    w_addr <= w_addr + (1 << w_size); w_left <= w_left - 1;
                end
                last_move <= cycle;
            end
            if (b_wait_on && b_wait != 0) b_wait <= b_wait - 1;
            if (bvalid && bready) begin
                b_wait_on <= 0; w_busy <= 0; last_move <= cycle;
            end
            if (arvalid && arready) begin
                o = odd(araddr, arlen, arsize, arburst, arlock);
                r_busy <= 1; r_addr <= araddr; r_left <= arlen; r_size <= arsize; r_id <= arid;
                r_wait <= lfsr[10:7];
                reads <= reads + 1;
                $display("%0d %s AR id=%0d addr=%h len=%0d size=%0d burst=%0d%s", cycle, NAME, arid, araddr,
                         arlen, arsize, arburst, o);
                if (o != "") odds <= odds + 1;
                last_move <= cycle;
            end
            if (r_busy && r_wait != 0) r_wait <= r_wait - 1;
            if (rvalid && rready) begin
                if (r_left == 0) r_busy <= 0;
                else begin
                    r_addr <= r_addr + (1 << r_size); r_left <= r_left - 1; r_wait <= lfsr[11:9];
                end
                last_move <= cycle;
            end
        end
    end

    function automatic string status();
        return $sformatf("%s: %0d writes, %0d reads, %0d odd; last move at %0d; open: %s%s%s",
            NAME, writes, reads, odds, last_move,
            w_busy ? (w_have ? "W-data " : "B ") : "", r_busy ? "R " : "",
            (!w_busy && !r_busy) ? "none" : "");
    endfunction
endmodule

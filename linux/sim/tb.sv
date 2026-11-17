// Boots Linux on linux_top in Verilator, with no harness: `mem` is an AXI4
// memory (../../sim/axi_mem.sv) that holds the ELF. The testbench is the host
// of the firmware's RTT console, as `hio cpu boot` is on a board: it prints
// what the core writes, types +keys at the first shell prompt, and ends with
// the exit status the firmware gives, or at a kernel panic.
//
//   make -C linux/sim ELF=<elf>      (CYCLES=<n> to stop there; KEYS=...;
//                                     STAMP=1 starts each line with the cycle)
module tb;
    logic clk = 0;
    always #5 clk = ~clk;
    longint unsigned cycle = 0;
    logic rst_n;
    assign rst_n = cycle >= 10;
    always @(posedge clk) cycle <= cycle + 1;

    __std___axi4_if____std___axi4_pkg__32__8__6__1__1__1__1__1 mem ();

    run_rocket_linux_linux_top dut (
        .i_clk(clk), .i_rst(rst_n), .i_dm_rst(rst_n),
        .i_dmi_psel(1'b0), .i_dmi_penable(1'b0), .i_dmi_pwrite(1'b0),
        .i_dmi_paddr(12'd0), .i_dmi_pwdata(32'd0), .o_dmi_prdata(), .o_dmi_pready(),
        .mem(mem.master)
    );

    axi_mem #(.NAME("mem"), .AW(32), .IW(6), .SEED(16'hace1), .LOG(0)) u_mem (
        .clk, .rst_n,
        .awvalid(mem.awvalid), .awready(mem.awready), .awid(mem.awid), .awaddr(mem.awaddr),
        .awlen(mem.awlen), .awsize(mem.awsize), .awburst(mem.awburst), .awlock(mem.awlock),
        .wvalid(mem.wvalid), .wready(mem.wready), .wdata(mem.wdata), .wstrb(mem.wstrb),
        .wlast(mem.wlast), .bvalid(mem.bvalid), .bready(mem.bready), .bid(mem.bid),
        .arvalid(mem.arvalid), .arready(mem.arready), .arid(mem.arid), .araddr(mem.araddr),
        .arlen(mem.arlen), .arsize(mem.arsize), .arburst(mem.arburst), .arlock(mem.arlock),
        .rvalid(mem.rvalid), .rready(mem.rready), .rid(mem.rid), .rdata(mem.rdata),
        .rlast(mem.rlast));

    assign mem.bresp = __std_axi4_config::resp_variants_OKAY; assign mem.buser = 0;
    assign mem.rresp = __std_axi4_config::resp_variants_OKAY; assign mem.ruser = 0;

    // cycles: stop there (0: never). rtt: the control block (elf2mem.py
    // finds it). poll: how often the host looks at the console.
    longint unsigned cycles = 0, rtt = 0, poll = 1000;
    bit stamp = 0;
    string keys = "";
    initial begin
        int f;
        longint unsigned a, d;
        string elf_mem = "prog.mem";
        void'($value$plusargs("cycles=%d", cycles));
        void'($value$plusargs("rtt=%h", rtt));
        void'($value$plusargs("poll=%d", poll));
        void'($value$plusargs("stamp=%d", stamp));
        if ($value$plusargs("keys=%s", keys)) keys = {keys, "\n"};
        if (rtt == 0) $fatal(1, "no _SEGGER_RTT in the ELF");
        f = $fopen(elf_mem, "r");
        if (f == 0) $fatal(1, "no %s: run elf2mem.py first", elf_mem);
        while ($fscanf(f, "%h %h", a, d) == 2) u_mem.words[a >> 3] = d;
        $fclose(f);
    end

    // The control block as fw.S lays it out: the id (16 bytes), the channel
    // counts (8 + 8), then up 0 (the terminal), up 1 (the exit status) and
    // down 0 (keys), each a name, a buffer, its size, and the write and read
    // offsets (8 bytes each). The firmware writes the id last.
    localparam longint unsigned RTT_ID = 64'h5220524547474553;  // "SEGGER R"
    localparam longint unsigned UP0 = 32, UP1 = 80, DOWN0 = 128;
    localparam longint unsigned BUF = 8, SIZE = 16, WR = 24, RD = 32;

    function automatic logic [7:0] peek8(longint unsigned addr);
        logic [63:0] w = u_mem.peek(addr);
        return w[(addr % 8) * 8 +: 8];
    endfunction
    function automatic void poke8(longint unsigned addr, logic [7:0] b);
        u_mem.poke(addr, {8{b}}, 8'(1 << (addr % 8)));
    endfunction
    function automatic void poke64(longint unsigned addr, longint unsigned d);
        u_mem.poke(addr, d, 8'hff);
    endfunction

    string tail = "";   // the last two bytes printed
    string line = "";   // the line being printed
    bit panic = 0;      // the kernel said it panicked
    int typed = -1;     // keys typed so far; -1 until the prompt
    longint unsigned typed_at = 0;

    function automatic bit has(string s, string sub);
        for (int i = 0; i + sub.len() <= s.len(); i++)
            if (s.substr(i, i + sub.len() - 1) == sub) return 1;
        return 0;
    endfunction

    // Print what the terminal channel holds, and free its space.
    function automatic void drain();
        longint unsigned ch = rtt + UP0;
        longint unsigned b = u_mem.peek(ch + BUF), size = u_mem.peek(ch + SIZE);
        longint unsigned wr = u_mem.peek(ch + WR), rd = u_mem.peek(ch + RD);
        if (rd == wr) return;
        while (rd != wr) begin
            logic [7:0] c = peek8(b + rd);
            if (stamp && line.len() == 0) $write("[%0d] ", cycle);
            $write("%c", c);
            if (c == 8'h0a) begin
                if (has(line, "Kernel panic")) panic = 1;
                line = "";
            end else line = {line, string'(c)};
            tail = {tail.len() > 0 ? tail.substr(tail.len() - 1, tail.len() - 1) : "", string'(c)};
            rd = rd + 1 == size ? 0 : rd + 1;
        end
        poke64(ch + RD, rd);
        $fflush();
    endfunction

    // Put what is left of the keys in the down channel, as far as it has room.
    function automatic void type_keys();
        longint unsigned ch = rtt + DOWN0;
        longint unsigned b = u_mem.peek(ch + BUF), size = u_mem.peek(ch + SIZE);
        longint unsigned wr = u_mem.peek(ch + WR), rd = u_mem.peek(ch + RD);
        while (typed < keys.len() && (wr + 1 == size ? 0 : wr + 1) != rd) begin
            poke8(b + wr, keys[typed]);
            typed++;
            wr = wr + 1 == size ? 0 : wr + 1;
        end
        poke64(ch + WR, wr);
    endfunction

    always @(posedge clk) begin
        if (rtt != 0 && cycle % poll == 0 && u_mem.peek(rtt) == RTT_ID) begin
            drain();
            if (typed < 0 && tail == "# " && keys.len() > 0) begin
                typed = 0;
                typed_at = cycle;
            end
            if (typed >= 0) type_keys();
            if (u_mem.peek(rtt + UP1 + WR) != u_mem.peek(rtt + UP1 + RD)) begin
                logic [7:0] status = peek8(u_mem.peek(rtt + UP1 + BUF) + u_mem.peek(rtt + UP1 + RD));
                $display("\n--- exit status %0d at cycle %0d (keys typed at cycle %0d) ---",
                         status, cycle, typed_at);
                $display("%s", u_mem.status());
                $finish;
            end
            if (panic) begin
                $display("\n--- kernel panic at cycle %0d ---", cycle);
                $display("%s", u_mem.status());
                $finish;
            end
        end
        if (cycles != 0 && cycle == cycles) begin
            if (rtt != 0) drain();
            $display("\n--- stopped at cycle %0d ---", cycle);
            $display("%s", u_mem.status());
            $finish;
        end
    end
endmodule

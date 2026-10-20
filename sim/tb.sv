// Runs an ELF on rocket_top in Verilator, with no harness: `mem` and `mmio`
// are AXI4 memories (axi_mem.sv) that answer late and log every transfer.
// The debug module's APB is left idle. At the end it prints the RTT console
// output and what each memory still has open.
//
//   make -C sim ELF=<elf>      (CYCLES=<n> to run longer)
module tb;
    logic clk = 0;
    always #5 clk = ~clk;
    longint unsigned cycle = 0;
    logic rst_n;
    assign rst_n = cycle >= 10;
    always @(posedge clk) cycle <= cycle + 1;

    __std___axi4_if____std___axi4_pkg__32__8__6__1__1__1__1__1 mem ();
    __std___axi4_if____std___axi4_pkg__18__8__4__1__1__1__1__1 mmio ();

    run_rocket_rocket_top dut (
        .i_clk(clk), .i_rst(rst_n), .i_dm_rst(rst_n),
        .i_dmi_psel(1'b0), .i_dmi_penable(1'b0), .i_dmi_pwrite(1'b0),
        .i_dmi_paddr(12'd0), .i_dmi_pwdata(32'd0), .o_dmi_prdata(), .o_dmi_pready(),
        .mem(mem.master), .mmio(mmio.master)
    );

    `define MEM_PORTS(IF) \
        .awvalid(IF.awvalid), .awready(IF.awready), .awid(IF.awid), .awaddr(IF.awaddr), \
        .awlen(IF.awlen), .awsize(IF.awsize), .awburst(IF.awburst), .awlock(IF.awlock), \
        .wvalid(IF.wvalid), .wready(IF.wready), .wdata(IF.wdata), .wstrb(IF.wstrb), \
        .wlast(IF.wlast), .bvalid(IF.bvalid), .bready(IF.bready), .bid(IF.bid), \
        .arvalid(IF.arvalid), .arready(IF.arready), .arid(IF.arid), .araddr(IF.araddr), \
        .arlen(IF.arlen), .arsize(IF.arsize), .arburst(IF.arburst), .arlock(IF.arlock), \
        .rvalid(IF.rvalid), .rready(IF.rready), .rid(IF.rid), .rdata(IF.rdata), \
        .rlast(IF.rlast)

    axi_mem #(.NAME("mem"), .AW(32), .IW(6), .SEED(16'hace1)) u_mem (
        .clk, .rst_n, `MEM_PORTS(mem));
    axi_mem #(.NAME("mmio"), .AW(18), .IW(4), .SEED(16'h5eed)) u_mmio (
        .clk, .rst_n, `MEM_PORTS(mmio));

    assign mem.bresp  = __std_axi4_config::resp_variants_OKAY; assign mem.buser  = 0;
    assign mem.rresp  = __std_axi4_config::resp_variants_OKAY; assign mem.ruser  = 0;
    assign mmio.bresp = __std_axi4_config::resp_variants_OKAY; assign mmio.buser = 0;
    assign mmio.rresp = __std_axi4_config::resp_variants_OKAY; assign mmio.ruser = 0;

    longint unsigned cycles = 200000, rtt = 0;
    initial begin
        int f;
        longint unsigned a, d;
        string elf_mem = "prog.mem";
        void'($value$plusargs("cycles=%d", cycles));
        void'($value$plusargs("rtt=%h", rtt));
        f = $fopen(elf_mem, "r");
        if (f == 0) $fatal(1, "no %s: run elf2mem.py first", elf_mem);
        while ($fscanf(f, "%h %h", a, d) == 2) u_mem.words[a >> 3] = d;
        $fclose(f);
    end

    // RTT up channel 0 of rtt-target on RV64: the control block holds the
    // id (16 bytes), the channel counts (8 + 8), then each up channel's
    // name, buffer, size, write and read offsets, and flags (8 bytes each).
    function automatic void dump_rtt();
        longint unsigned buf_addr, size, wr;
        string s = "";
        buf_addr = u_mem.peek(rtt + 'h28);
        size     = u_mem.peek(rtt + 'h30);
        wr       = u_mem.peek(rtt + 'h38);
        $display("--- RTT up 0: buffer %h, size %0d, write offset %0d ---", buf_addr, size, wr);
        for (longint unsigned i = 0; i < wr && i < size; i++) begin
            logic [63:0] w = u_mem.peek(buf_addr + i);
            s = {s, string'(w[((buf_addr + i) % 8) * 8 +: 8])};
        end
        $display("%s", s);
        $display("--- end ---");
    endfunction

    always @(posedge clk) begin
        if (cycle == cycles) begin
            if (rtt != 0) dump_rtt();
            $display("%s", u_mem.status());
            $display("%s", u_mmio.status());
            $display("pc of the last retired instruction: see the log above");
            $finish;
        end
    end
endmodule

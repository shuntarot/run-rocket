// Checks that cflush.d.l1 x0, run from the debug program buffer, writes the
// data cache back to memory: `make -C linux/sim cflush`. The core is
// ../cflush's (a blocking data cache); ../'s takes cflush.d.l1 as a no-op.
//
// The core stores a word to a cached line and spins. The line is then dirty
// in the data cache, so memory still holds the old word. The testbench halts
// the hart through the DMI, runs a nop from the program buffer (memory must
// not change), then cflush.d.l1 x0 (memory must now hold the new word).
module tb_cflush;
    logic clk = 0;
    always #5 clk = ~clk;
    longint unsigned cycle = 0;
    logic rst_n;
    assign rst_n = cycle >= 10;
    always @(posedge clk) cycle <= cycle + 1;

    logic        psel = 0, penable = 0, pwrite = 0;
    logic [11:0] paddr = 0;
    logic [31:0] pwdata = 0, prdata;
    logic        pready;

    __std___axi4_if____std___axi4_pkg__32__8__6__1__1__1__1__1 mem ();

    run_rocket_linux_cflush_linux_top dut (
        .i_clk(clk), .i_rst(rst_n), .i_dm_rst(rst_n),
        .i_dmi_psel(psel), .i_dmi_penable(penable), .i_dmi_pwrite(pwrite),
        .i_dmi_paddr(paddr), .i_dmi_pwdata(pwdata), .o_dmi_prdata(prdata),
        .o_dmi_pready(pready),
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

    // DMI registers (register n is at byte n * 4 on the APB)
    localparam int DMCONTROL = 'h10, DMSTATUS = 'h11, ABSTRACTCS = 'h16,
                   COMMAND = 'h17, PROGBUF0 = 'h20, PROGBUF1 = 'h21;
    // Postexec only: run the program buffer, transfer no register.
    localparam logic [31:0] POSTEXEC = 32'h0034_1000;
    localparam logic [31:0] CFLUSH = 32'hfc00_0073, NOP = 32'h0000_0013,
                            EBREAK = 32'h0010_0073;

    localparam longint unsigned A = 64'h8010_0000;   // the cached word
    localparam logic [63:0] OLD = 64'h1111_1111_1111_1111;
    localparam logic [31:0] NEW = 32'h2222_2222;

    task automatic dmi_write(int r, logic [31:0] d);
        @(posedge clk); psel <= 1; pwrite <= 1; paddr <= 12'(r * 4); pwdata <= d;
        @(posedge clk); penable <= 1;
        do @(posedge clk); while (!pready);
        psel <= 0; penable <= 0; pwrite <= 0;
    endtask

    task automatic dmi_read(int r, output logic [31:0] d);
        @(posedge clk); psel <= 1; pwrite <= 0; paddr <= 12'(r * 4);
        @(posedge clk); penable <= 1;
        do @(posedge clk); while (!pready);
        d = prdata;
        psel <= 0; penable <= 0;
    endtask

    // Run one instruction from the program buffer; give cmderr.
    task automatic exec(logic [31:0] insn, output logic [2:0] cmderr);
        logic [31:0] cs;
        dmi_write(PROGBUF0, insn);
        dmi_write(PROGBUF1, EBREAK);
        dmi_write(COMMAND, POSTEXEC);
        do dmi_read(ABSTRACTCS, cs); while (cs[12]);
        cmderr = cs[10:8];
        if (cmderr != 0) dmi_write(ABSTRACTCS, 32'h0000_0700);
    endtask

    int fails = 0;
    task automatic expect_mem(string when, logic [63:0] want);
        logic [63:0] got = u_mem.peek(A);
        $display("%-40s memory at %h: %h (want %h) %s", when, A, got, want,
                 got == want ? "ok" : "FAIL");
        if (got != want) fails++;
    endtask

    initial begin
        logic [31:0] st;
        logic [2:0]  err;
        // At 0x8000_0000, where the boot ROM jumps:
        //   auipc s0, 0x100        s0 = A
        //   lui   t0, 0x22222
        //   addi  t0, t0, 0x222    t0 = NEW
        //   sw    t0, 0(s0)
        //   j     .
        u_mem.words[64'h8000_0000 >> 3] = 64'h2222_22b7_0010_0417;
        u_mem.words[64'h8000_0008 >> 3] = 64'h0054_2023_2222_8293;
        u_mem.words[64'h8000_0010 >> 3] = 64'h0000_0000_0000_006f;
        u_mem.words[A >> 3] = OLD;

        repeat (20000) @(posedge clk);
        expect_mem("after the store, running", OLD);

        dmi_write(DMCONTROL, 32'h0000_0001);
        dmi_write(DMCONTROL, 32'h8000_0001);
        do dmi_read(DMSTATUS, st); while (!st[9]);
        dmi_write(DMCONTROL, 32'h0000_0001);
        $display("halted at cycle %0d", cycle);
        expect_mem("halted", OLD);

        exec(NOP, err);
        $display("nop from the program buffer: cmderr %0d", err);
        if (err != 0) fails++;
        repeat (1000) @(posedge clk);
        expect_mem("after a nop", OLD);

        exec(CFLUSH, err);
        $display("cflush.d.l1 x0 from the program buffer: cmderr %0d", err);
        if (err != 0) fails++;
        repeat (1000) @(posedge clk);
        expect_mem("after cflush.d.l1 x0", {OLD[63:32], NEW});

        if (fails == 0) $display("cflush: ok");
        else $display("cflush: FAIL (%0d)", fails);
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk);
        $fatal(1, "timed out");
    end
endmodule

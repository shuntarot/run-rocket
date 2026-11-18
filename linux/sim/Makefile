# make -C linux/sim    boots ../linux.elf on linux_top in Verilator (5.x)
#
# ELF=<elf> boots another; CYCLES=<n> stops there; KEYS is typed at the
# first shell prompt (the default powers off, which ends the run); STAMP=1
# starts each console line with the cycle.
#
# make -C linux/sim cflush    checks, on the core of ../cflush, that
#                             cflush.d.l1 x0 run from the debug program
#                             buffer writes the data cache back
-include ../../local.mk
VERILATOR ?= verilator
ELF       ?= ../linux.elf
CYCLES    ?= 0
KEYS      ?= cat /proc/cpuinfo; exit
STAMP     ?= 0
JOBS      ?= 8
AXI       := ../dependencies/std/axi_if/axi_pkg.sv ../dependencies/std/axi_if/axi_if.sv
SV        := ../rtl/linux_top.sv

run: obj_dir/Vtb
	python3 -I ../../sim/elf2mem.py $(ELF) prog.mem > rtt.txt
	obj_dir/Vtb +cycles=$(CYCLES) +rtt=$$(cat rtt.txt) +stamp=$(STAMP) '+keys=$(KEYS)'

obj_dir/Vtb: tb.sv ../../sim/axi_mem.sv $(SV)
	$(VERILATOR) --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
		--build-jobs $(JOBS) --top-module tb tb.sv ../../sim/axi_mem.sv $(AXI) $(SV)

# The core of ../cflush: LinuxRocket with a blocking data cache and cflush.d.l1
CFLUSH_AXI := ../cflush/dependencies/std/axi_if/axi_pkg.sv ../cflush/dependencies/std/axi_if/axi_if.sv
CFLUSH_SV  := ../cflush/rtl/linux_top.sv

cflush: obj_cflush/Vtb_cflush
	obj_cflush/Vtb_cflush

obj_cflush/Vtb_cflush: tb_cflush.sv ../../sim/axi_mem.sv $(CFLUSH_SV)
	$(VERILATOR) --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
		--build-jobs $(JOBS) --Mdir obj_cflush --top-module tb_cflush \
		tb_cflush.sv ../../sim/axi_mem.sv $(CFLUSH_AXI) $(CFLUSH_SV)

$(CFLUSH_SV): ../rtl/linux_top.veryl ../cflush/rtl/LinuxRocket.v ../cflush/Veryl.lock
	$(MAKE) -C ../cflush
	cd ../cflush && veryl build

$(SV): ../rtl/linux_top.veryl ../rtl/LinuxRocket.v ../Veryl.lock
	cd .. && veryl build

clean:
	rm -rf obj_dir obj_cflush prog.mem rtt.txt

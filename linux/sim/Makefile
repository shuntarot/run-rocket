# make -C linux/sim    boots ../linux.elf on linux_top in Verilator (5.x)
#
# ELF=<elf> boots another; CYCLES=<n> stops there; KEYS is typed at the
# first shell prompt (the default powers off, which ends the run); STAMP=1
# starts each console line with the cycle.
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

$(SV): ../rtl/linux_top.veryl ../rtl/LinuxRocket.v ../Veryl.lock
	cd .. && veryl build

clean:
	rm -rf obj_dir prog.mem rtt.txt

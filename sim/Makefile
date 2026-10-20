# make -C sim ELF=<elf>    runs an ELF on rocket_top in Verilator (5.x)
-include ../local.mk
VERILATOR ?= verilator
ELF       ?= ../asm/smoke.elf
CYCLES    ?= 200000
AXI       := ../dependencies/std/axi_if/axi_pkg.sv ../dependencies/std/axi_if/axi_if.sv
SV        := ../rtl/rocket_top.sv

run: obj_dir/Vtb
	python3 -I elf2mem.py $(ELF) prog.mem > rtt.txt
	obj_dir/Vtb +cycles=$(CYCLES) +rtt=$$(cat rtt.txt)

obj_dir/Vtb: tb.sv axi_mem.sv $(SV)
	$(VERILATOR) --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style \
		--top-module tb tb.sv axi_mem.sv $(AXI) $(SV)

$(SV): ../rtl/rocket_top.veryl ../rtl/MiniRocket.v ../Veryl.lock
	cd .. && veryl build

clean:
	rm -rf obj_dir prog.mem rtt.txt

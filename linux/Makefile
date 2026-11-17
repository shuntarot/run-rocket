# make -C linux    builds linux.elf: Linux with busybox on LinuxRocket, console
#                  on RTT
#
# The kernel, the firmware and the way they are put together are
# run-heliodor's (linux/ there): the same kernel runs on both cores. Build
# its kernel first (`make -C <run-heliodor>/linux`), and say where it is in
# local.mk (HELIODOR). The firmware is built for this core: it emulates the
# `time` CSR, which Rocket lacks, does the misaligned loads and stores Rocket
# traps on, and opens memory to S-mode through PMP.
-include ../local.mk
LINUX_CROSS ?= riscv64-unknown-linux-gnu-
HELIODOR    ?= ../../run-heliodor
H := $(HELIODOR)/linux

# Where fw.S puts the device tree: in memory, past the kernel.
DTB_ADDR := 0x81e00000

.PHONY: all clean
all: linux.elf

# One hart; the kernel Image is H/build/Image (image.S takes it from there).
linux.elf: $(H)/fw.S $(H)/image.S $(H)/link.ld $(H)/build/Image build/rocket.dtb
	$(LINUX_CROSS)gcc -march=rv64imac_zicsr_zifencei -mabi=lp64 -nostdlib -static \
		-DDTB_ADDR=$(DTB_ADDR) -Wl,--defsym=DTB_ADDR=$(DTB_ADDR) \
		-DDTB_FILE='"$(abspath build/rocket.dtb)"' -DNHARTS=1 -DEMULATE_TIME -DEMULATE_MISALIGNED -DPMP \
		-Wa,-I$(H) -T $(H)/link.ld -o $@ $(H)/fw.S $(H)/image.S

build/%.dtb: %.dts
	mkdir -p build
	dtc -I dts -O dtb -o $@ $<

clean:
	rm -rf linux.elf build

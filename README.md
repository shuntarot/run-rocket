# run-rocket

Runs a [rocket-chip](https://github.com/chipsalliance/rocket-chip) RV64 core
(`MiniRocket`: one RV64IMAC Rocket core, no VM, FPU or BTB) on a Digilent Arty
A7-35 with [veryl-harness](https://github.com/shuntarot/uharness).
The core runs from the board's DDR3 at 0x8000_0000 (`mem`). Its MMIO port
goes to 1 KB of FPGA memory at 0x2_0000 (`mmio`), and its Debug Module is
reached over the harness (`dmi`).

## Requirements

- Veryl, with `veryl-harness` and `hio` from veryl-harness
- Vivado
- An Arty A7-35 on USB
- Rust through rustup, for the firmware (`rust-toolchain.toml` picks the target)
- A RISC-V GCC, for `asm/smoke.S` (`CROSS` in `local.mk`)

## Run

```bash
veryl harness gen --target digilent/arty-a7-35
make -C hns/syn
hio program
hio run bringup.hio
```

`bringup.hio` loads `asm/smoke.elf`, runs it, and reads back what it wrote.
The expected values are in its comments.

Firmware in Rust runs with cargo. `hio cpu boot` loads it, connects to its RTT
console, and exits with its status; Ctrl-A x leaves. If `veryl harness gen`
wrote somewhere other than `hns/` (`--out-dir`), change the path of
`HIO_REGS` under `[env]` in `.cargo/config.toml` to match.

```bash
cargo run -p hello
cargo run -p console
```

riscv-tests' `isa` tests run one by one through `hio cpu boot`, each ending
with its pass or failure code (a test that hangs times out after 60 s):

```bash
scripts/riscv-tests.sh <riscv-tests>/share/riscv-tests/isa          # the suites this core runs
scripts/riscv-tests.sh -o results.txt <isa dir> 'rv64ui-p-*'   # or name them
```

On the Arty A7-35 and the VCU118, 83 of the 104 pass. The rest fail by design
of this core:

- `rv64ua-p-*` (19): the core has no data cache, and the DRAM port is AXI4,
  which has no atomic operations. An AMO to DRAM traps.
- `rv64ui-p-ma_data`: no misaligned access.
- `rv64mi-p-zicntr`: the core has no user mode, so it has no `cycle` and
  `instret` (it has `mcycle` and `minstret`).

The core's Debug Module is reached the same way:

```bash
hio cpu halt               # also: step, regs, resume, reset --halt, info
```

The console has a debug prompt as well (Ctrl-A c).

## Size

LUT and FF counts, block RAM in 36 Kb blocks, after place and route. The
core is the DUT alone; the design adds the harness and the memory behind it
(block RAM, or the board's memory controller; the PYNQ-Z1's is hard silicon
in its PS and is not counted).

| Target | Clock | Core LUT / FF / BRAM / DSP | Design LUT / FF / BRAM / DSP |
|---|---|---|---|
| `digilent/arty-a7-35` | 50 MHz | 9,890 / 4,416 / 5.5 / 0 | 16,838 / 10,332 / 6.5 / 0 |
| `digilent/pynq-z1` | 50 MHz | 9,856 / 4,414 / 5.5 / 0 | 11,024 / 5,614 / 6.5 / 0 |
| `xilinx/vcu118` | 50 MHz | 9,898 / 4,419 / 5 / 0 | 29,546 / 26,867 / 31.5 / 3 |

## Files

| | |
|---|---|
| `rtl/rocket_top.veryl` | the DUT: `MiniRocket` with its debug module on APB |
| `rtl/MiniRocket.v` | the core, generated from rocket-chip v1.6 |
| `Harness.toml` | where each port goes |
| `asm/smoke.S` | the test program (`make -C asm`) |
| `bsp/` | startup, console (RTT) and exit for the firmware |
| `apps/` | the firmware: `hello`, `console` |
| `sim/` | the DUT alone in Verilator (`make -C sim ELF=<elf>`) |

Put paths for your machine in `local.mk` (`CROSS`, `VERILATOR`).

## License

MIT (`LICENSE`), except the core in `rtl/MiniRocket.v`, which is under the
licenses of rocket-chip (`rtl/LICENSE.Berkeley`, `rtl/LICENSE.SiFive`).

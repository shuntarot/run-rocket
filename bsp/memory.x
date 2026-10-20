/* MiniRocket on run-rocket's harness. `mem` is DRAM from 0x8000_0000, the
 * reset PC. The core caches fetches only; its loads and stores to DRAM are
 * uncached, so the host sees what the core writes at once. The RTT console
 * still goes to a section of its own, past the program. */

MEMORY
{
  RAM     (rwx) : ORIGIN = 0x80000000, LENGTH = 32M
  CONSOLE (rw)  : ORIGIN = 0x82000000, LENGTH = 64K
}

REGION_ALIAS("REGION_TEXT",   RAM);
REGION_ALIAS("REGION_RODATA", RAM);
REGION_ALIAS("REGION_DATA",   RAM);
REGION_ALIAS("REGION_BSS",    RAM);
REGION_ALIAS("REGION_HEAP",   RAM);
REGION_ALIAS("REGION_STACK",  RAM);

_max_hart_id     = 0;
_hart_stack_size = 64K;
_heap_size       = 0;

SECTIONS
{
  /* Set up at run time by rtt_init!: nothing is loaded or zeroed here.
   * After .bss, it would move __ebss and the startup would zero 32 MB. */
  .console (NOLOAD) : ALIGN(64)
  {
    *(.console .console.*);
  } > CONSOLE
}
INSERT AFTER .uninit;

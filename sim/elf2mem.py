#!/usr/bin/env python3
"""Writes the loadable segments of an ELF64 as `address word` lines (hex,
64-bit words, little endian) for tb.sv, zeros past the file bytes included,
and prints the address of `_SEGGER_RTT` (0 if there is none).

    elf2mem.py <elf> <out>
"""
import struct
import sys


def main():
    raw = open(sys.argv[1], "rb").read()
    assert raw[:4] == b"\x7fELF" and raw[4] == 2, "an ELF64 is expected"
    phoff, shoff = struct.unpack_from("<QQ", raw, 0x20)
    phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from("<HHHHH", raw, 0x36)
    words = {}
    for i in range(phnum):
        p_type, _, p_offset, _, p_paddr, p_filesz, p_memsz, _ = struct.unpack_from(
            "<IIQQQQQQ", raw, phoff + i * phentsize)
        if p_type != 1 or p_memsz == 0:
            continue
        data = raw[p_offset:p_offset + p_filesz] + bytes(p_memsz - p_filesz)
        for off in range(len(data)):
            a = p_paddr + off
            w = words.setdefault(a >> 3, bytearray(8))
            w[a & 7] = data[off]
    with open(sys.argv[2], "w") as out:
        for w in sorted(words):
            out.write("%x %x\n" % (w << 3, int.from_bytes(words[w], "little")))
    rtt = 0
    for i in range(shnum):
        name, typ, _, _, off, size, link, _, _, entsize = struct.unpack_from(
            "<IIQQQQIIQQ", raw, shoff + i * shentsize)
        if typ != 2:
            continue
        strtab = struct.unpack_from("<IIQQQQIIQQ", raw, shoff + link * shentsize)
        stroff = strtab[4]
        for j in range(size // entsize):
            st_name, _, _, _, st_value, _ = struct.unpack_from("<IBBHQQ", raw, off + j * entsize)
            end = raw.index(b"\0", stroff + st_name)
            if raw[stroff + st_name:end] == b"_SEGGER_RTT":
                rtt = st_value
    print("%x" % rtt)


main()

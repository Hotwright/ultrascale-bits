#!/usr/bin/env python3
"""Write a U-Boot script image that loads a bitstream and a bare-metal
program (sw/build.sh baremetal ... -> <prog>.bin) from the KV260's SD card
and runs it. No mkimage needed: this writes the legacy image header itself.

    mkscr.py <out.scr> <dir on the SD boot partition> <bitstream.bit> <prog.bin>

At the U-Boot prompt (stop autoboot with a key):

    fatload mmc 1:1 0x10000000 <dir>/<out.scr>; source 0x10000000

U-Boot runs at EL2 with its caches on; the script turns them off so the
program runs as it does from JTAG (MMU off, every access Device memory).
OCM is reserved to fatload, so the program goes through DDR. The program
does not return: power-cycle (or reset) to get back to Linux.
"""
import binascii
import struct
import sys
import time

OCM = 0xFFFC0000


def script(d, bit, prog):
    return (
        "echo hotwright: %(d)s/%(bit)s + %(d)s/%(prog)s\n"
        "fatload mmc 1:1 0x18000000 %(d)s/%(bit)s && fpga loadb 0 0x18000000 ${filesize} && "
        "fatload mmc 1:1 0x10000000 %(d)s/%(prog)s && cp.b 0x10000000 0x%(ocm)x ${filesize} && "
        "dcache off && icache off && go 0x%(ocm)x\n" % dict(d=d, bit=bit, prog=prog, ocm=OCM))


def image(text, name):
    body = text.encode()
    data = struct.pack(">II", len(body), 0) + body
    # magic, hcrc, time, size, load, ep, dcrc, os (Linux), arch (ARM64),
    # type (script), comp (none), name
    hdr = lambda hcrc: struct.pack(">IIIIIIIBBBB32s", 0x27051956, hcrc, int(time.time()), len(data),
                                   0, 0, binascii.crc32(data), 5, 22, 6, 0, name.encode()[:32])
    return hdr(binascii.crc32(hdr(0))) + data


def main():
    out, d, bit, prog = sys.argv[1:5]
    open(out, "wb").write(image(script(d.strip("/"), bit, prog), "hotwright " + prog))


if __name__ == "__main__":
    main()

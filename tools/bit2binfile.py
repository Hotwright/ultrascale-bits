#!/usr/bin/env python3
# Convert a Xilinx .bit into the .bit.bin the Zynq UltraScale+ FPGA manager
# loads, without bootgen.
#
# The format is simpler than its reputation. A .bit is a short tagged header --
# a length-prefixed magic, then keys 'a' (design name), 'b' (part), 'c' (date),
# 'd' (time), each with a 16-bit big-endian length -- followed by key 'e' with a
# 32-bit big-endian length and the raw configuration stream. The .bin is that
# stream with every 32-bit word byte-swapped, and nothing else:
#
#   bootgen -image x.bif -arch zynqmp -process_bitstream bin
#
# produces a file of exactly the 'e' payload's length, and this tool reproduces
# it byte for byte -- verified on a Vivado-generated xck26 bitstream, 7,797,692
# bytes, with --verify.
#
# Load it on the board with:
#   sudo cp design.bit.bin /lib/firmware/
#   sudo fpgautil -b /lib/firmware/design.bit.bin -f Full
# (or echo the name into /sys/class/fpga_manager/fpga0/firmware with
# flags=0 for a full reconfiguration).
import argparse
import struct
import sys


def parse_bit(data):
    """Return (header fields dict, configuration stream bytes)."""
    if len(data) < 2:
        raise ValueError("file is too short to be a .bit")
    pos = 0
    magic_len = struct.unpack_from(">H", data, pos)[0]
    pos += 2 + magic_len
    pos += 2  # the 0x0001 that follows the magic
    fields = {}
    while pos < len(data):
        key = chr(data[pos])
        pos += 1
        if key == "e":
            (length,) = struct.unpack_from(">I", data, pos)
            pos += 4
            stream = data[pos:pos + length]
            if len(stream) != length:
                raise ValueError(
                    "truncated: key 'e' claims %d bytes, %d present" %
                    (length, len(stream)))
            return fields, stream
        (length,) = struct.unpack_from(">H", data, pos)
        pos += 2
        fields[key] = data[pos:pos + length].rstrip(b"\0").decode(
            "ascii", "replace")
        pos += length
    raise ValueError("no key 'e' -- this does not look like a .bit")


def byteswap32(b):
    if len(b) % 4:
        raise ValueError("configuration stream is not a whole number of "
                         "32-bit words (%d bytes)" % len(b))
    return b"".join(b[i:i + 4][::-1] for i in range(0, len(b), 4))


def main():
    ap = argparse.ArgumentParser(
        description="Convert a Xilinx .bit into a Zynq UltraScale+ .bit.bin")
    ap.add_argument("bit", help="input .bit")
    ap.add_argument("bin", nargs="?", help="output .bit.bin (default: <bit>.bin)")
    ap.add_argument("--verify", metavar="REF",
                    help="compare the result against a reference .bit.bin "
                         "(e.g. one bootgen produced) and exit non-zero on a "
                         "mismatch")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    data = open(args.bit, "rb").read()
    fields, stream = parse_bit(data)
    out = byteswap32(stream)

    if not args.quiet:
        print("design : %s" % fields.get("a", "?"))
        print("part   : %s" % fields.get("b", "?"))
        print("built  : %s %s" % (fields.get("c", "?"), fields.get("d", "?")))
        print("stream : %d bytes (%d words)" % (len(out), len(out) // 4))

    if args.verify:
        ref = open(args.verify, "rb").read()
        if ref == out:
            print("verify : identical to %s" % args.verify)
        else:
            n = sum(1 for a, b in zip(ref, out) if a != b)
            print("verify : DIFFERS from %s -- %d of %d bytes, lengths %d vs %d"
                  % (args.verify, n, min(len(ref), len(out)), len(ref), len(out)),
                  file=sys.stderr)
            return 1

    path = args.bin or (args.bit + ".bin")
    with open(path, "wb") as f:
        f.write(out)
    if not args.quiet:
        print("wrote  : %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

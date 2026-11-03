#!/bin/bash
# The tokenizer-sm block on the board, from the PS debug port (no Linux needed):
# load tokenizer.c, stream a line through, read the tokens; load tokenizer1.c
# over it (no new bitstream) and do it again. Expects `make hot` to have been
# run in hotc's blocks/ai/tokenizer-sm (build.sh does `make generate`; this
# needs build_rt/ too).
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BLK="${HOTC:-$ROOT/../hotc}/blocks/ai/tokenizer-sm"
[ -d "$BLK/build_rt" ] || make -s -C "$BLK" hot > /dev/null
python3 - "$BLK" <<'PY' > "$HERE/test.tcl"
import sys, re
blk = sys.argv[1]
def mem(p): return [int(l.split("//")[0], 16) for l in open(p) if l.split("//")[0].strip()]
text = b"Hello, World 42! x1 = f(y);\n"
pad = text + b"\n" * ((4 - len(text) % 4) % 4 + 4)
words = [int.from_bytes(pad[i:i+4], "little") for i in range(0, len(pad), 4)]
classes = {"tokenizer": rb"[A-Za-z]+", "tokenizer1": rb"[A-Za-z0-9()\[\]{}<>=;:_]+"}
B = 0xA0000000
out = ["proc w {a d} { mwr -force $a $d }", "proc r {a} { return [mrd -force -value $a] }", "set fails 0"]
for prog in ("tokenizer", "tokenizer1"):
    sm = mem(f"{blk}/build_rt/{prog}/{prog}_smdata.mem")
    vd = mem(f"{blk}/build_rt/{prog}/{prog}_vardata.mem")
    want = b"".join(m + b"\n" for m in re.findall(classes[prog], text))
    out.append(f"w 0x{B+0x1000:08x} 1; w 0x{B+0x1000:08x} 0")
    out.append("foreach v {" + " ".join(f"0x{v:x}" for v in vd) + f"}} {{ w 0x{B+0x20000:08x} $v }}")
    out.append("foreach v {" + " ".join(f"0x{v:x}" for v in sm) + f"}} {{ w 0x{B+0x10000:08x} $v }}")
    out.append(f"w 0x{B+0x1000:08x} 1; w 0x{B+0x1000:08x} 0")
    out.append(f"set fl [r 0x{B+0x10004:08x}]")
    out.append("foreach v {" + " ".join(f"0x{v:08x}" for v in words) + f"}} {{ w 0x{B:08x} $v }}")
    out.append("after 20")
    out.append(f"set st [r 0x{B+0x10000:08x}]; set got {{}}")
    out.append(f"while {{($st >> 16) > 0}} {{ set n [expr {{($st >> 16) >= 4 ? 4 : ($st >> 16)}}]; set v [r 0x{B:08x}]; "
               f"for {{set k 0}} {{$k < $n}} {{incr k}} {{ append got [format %c [expr {{($v >> (8*$k)) & 255}}]] }}; set st [r 0x{B+0x10000:08x}] }}")
    exp = want.decode().replace("\n", "|")
    out.append(f"set g [string map {{\\n |}} $got]")
    out.append(f"if {{$g eq {{{exp}}}}} {{ puts \"ok   {prog}.c: $g  (flags [format 0x%x $fl])\" }} "
               f"else {{ incr fails; puts \"FAIL {prog}.c: got '$g' want '{exp}' (flags [format 0x%x $fl], status [format 0x%08x $st])\" }}")
out.append('puts [expr {$fails == 0 ? "TOKENIZER-SM PASS" : "TOKENIZER-SM FAIL"}]')
print("\n".join(out))
PY
timeout 600 "$ROOT/env/kv260_xsdb.sh" < "$HERE/test.tcl" | tr -cd '\11\12\15\40-\176' | grep -aE "ok |FAIL|PASS|rror"

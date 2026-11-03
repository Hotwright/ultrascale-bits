#!/bin/bash
# Fill the SDP RAMB18 through the bridge, read it back, report wrong words and bit lanes.
# More checks, run the same way (env/kv260_xsdb.sh < file): collision.tcl (a write
# and a read of one address on one clock), lanes.tcl (byte and halfword strobes),
# same_address.tcl (read, write, read an address with no other read between).
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
timeout 900 "$ROOT/env/kv260_xsdb.sh" < "$HERE/test.tcl" | tr -cd '\11\12\15\40-\176' | grep -aE "^id|addr|fill|init|SDP-BRAM|rror|==="

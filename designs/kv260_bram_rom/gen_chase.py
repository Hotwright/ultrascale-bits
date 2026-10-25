#!/usr/bin/env python3
"""Write chase.hex for rom.v: 4096 bytes of Pmod LED patterns.

LED i (left to right on the Pmod LED module) is pmod[MAP[i]], and the LEDs are
active low, so each word is the complement of the lit set.
"""
MAP = [3, 7, 2, 6, 1, 5, 0, 4]
bounce = list(range(8)) + list(range(6, 0, -1))  # 0..7..1, period 14
with open("chase.hex", "w") as f:
    for a in range(4096):
        if a < 2048:
            on = 1 << MAP[bounce[a % 14]]  # one LED bouncing
        else:
            on = sum(1 << MAP[i] for i in range(8) if i <= a % 8)  # bar filling up
        f.write("%02x\n" % (~on & 0xFF))

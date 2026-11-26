"""Draw Forever UI's small tracker glyphs as transparent 32-bit TGA files."""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "Art")
SIZE, AA = 64, 3
GOLD = (255, 255, 255)  # tinted at runtime for status and theme colours


def segment(x, y, a, b, radius):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - a[0] - t * dx, y - a[1] - t * dy) <= radius


def ring(x, y, cx, cy, rx, ry, angle):
    c, s = math.cos(angle), math.sin(angle)
    u, v = (x-cx)*c + (y-cy)*s, -(x-cx)*s + (y-cy)*c
    return abs(math.sqrt((u/rx)**2 + (v/ry)**2) - 1) < 0.22


def glyph(kind, x, y):
    if kind == "complete":
        return segment(x,y,(10,33),(25,47),4.4) or segment(x,y,(25,47),(54,16),4.4)
    if kind == "quest":
        return segment(x,y,(32,12),(32,39),4.6) or math.hypot(x-32,y-51) < 5
    if kind == "unknown":
        a = math.atan2(y-25, x-31)
        arc = abs(math.hypot(x-31,y-25)-12) < 4 and (a < 0.5 or a > 2.85)
        return arc or segment(x,y,(41,30),(32,39),4) or math.hypot(x-32,y-50) < 4
    if kind == "chain":
        return ring(x,y,23,39,9,15,0.72) or ring(x,y,41,24,9,15,0.72)
    return False


os.makedirs(OUT, exist_ok=True)
for kind in ("complete", "quest", "unknown", "chain"):
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            coverage = sum(glyph(kind, x+(sx+0.5)/AA, y+(sy+0.5)/AA)
                           for sy in range(AA) for sx in range(AA))
            alpha = round(coverage * 255 / (AA*AA))
            pixels.extend((GOLD[2], GOLD[1], GOLD[0], alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(os.path.join(OUT, "tracker-" + kind + ".tga"), "wb") as output:
        output.write(header + pixels)

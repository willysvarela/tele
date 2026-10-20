"""Generate the 1024x1024 app icon with only the standard library: dark field, white rounded screen, red power dot."""
import struct, zlib, math, sys

S = 1024
BG = (0x15, 0x16, 0x1a)
SCREEN = (0xf5, 0xf5, 0xf7)
DOT = (0xe5, 0x09, 0x14)

def rounded_sdf(px, py, cx, cy, hw, hh, r):
    dx = abs(px - cx) - (hw - r)
    dy = abs(py - cy) - (hh - r)
    return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - r

def cov(d): return max(0.0, min(1.0, 0.5 - d))
def blend(dst, src, a): return tuple(int(round(d + (s - d) * a)) for d, s in zip(dst, src))

rows = []
for y in range(S):
    row = bytearray([0])
    for x in range(S):
        px, py = x + 0.5, y + 0.5
        c = BG
        a = cov(rounded_sdf(px, py, 512, 480, 330, 210, 44))
        if a: c = blend(c, SCREEN, a)
        d = math.hypot(px - 760, py - 630) - 34
        a = cov(d)
        if a: c = blend(c, DOT, a)
        a = cov(rounded_sdf(px, py, 512, 740, 120, 18, 18))
        if a: c = blend(c, (0x3a, 0x3c, 0x45), a)
        row += bytes(c)
    rows.append(bytes(row))

def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', S, S, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
print('wrote', sys.argv[1])

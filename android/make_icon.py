# Draws the launcher icon (neon octagon + kart) as a PNG without any image library.
import math, struct, sys, zlib

def render(size):
    ss = 3  # supersampling
    n = size * ss
    c = n / 2
    ring_r, ring_w = n * 0.36, n * 0.045
    px = bytearray()
    def octagon_dist(x, y):
        # distance-like metric to a regular octagon of "radius" 1 (rotated 22.5 deg)
        a = math.atan2(y, x) + math.pi / 8
        sector = (a % (math.pi / 4)) - math.pi / 8
        return math.hypot(x, y) * math.cos(sector) / math.cos(math.pi / 8)
    rows = []
    for y in range(n):
        row = []
        for x in range(n):
            dx, dy = (x - c) / ring_r, (y - c) / ring_r
            r, g, b = 9, 5, 16  # background
            # stripes
            ang = math.atan2(dy, dx)
            if int((ang + math.pi) / (math.pi / 3)) % 2:
                r, g, b = 22, 9, 30
            d = octagon_dist(dx, dy)
            if d < 1:
                r, g, b = 7, 4, 13
            edge = abs(d - 1) * ring_r
            if edge < ring_w:
                r, g, b = 255, 61, 240
            elif edge < ring_w * 3:
                k = 1 - (edge - ring_w) / (ring_w * 2)
                r, g, b = int(r + (255 - r) * k * 0.35), int(g + (61 - g) * k * 0.35), int(b + (240 - b) * k * 0.35)
            # kart pointing up: body triangle-ish + helmet
            kx, ky = dx / 0.55, dy / 0.55
            if abs(kx) < 0.42 * (1 - (-ky + 0.9) / 2.2) + 0.05 and -0.95 < ky < 0.8:
                r, g, b = 56, 214, 255
            if abs(kx) > 0.42 and abs(kx) < 0.62 and (-0.6 < ky < -0.2 or 0.25 < ky < 0.75):
                r, g, b = 56, 214, 255
            if math.hypot(kx, ky - 0.15) < 0.16:
                r, g, b = 255, 255, 255
            row.append((r, g, b))
        rows.append(row)
    out = bytearray()
    for y in range(size):
        out.append(0)
        for x in range(size):
            acc = [0, 0, 0]
            for sy in range(ss):
                for sx in range(ss):
                    p = rows[y * ss + sy][x * ss + sx]
                    acc[0] += p[0]; acc[1] += p[1]; acc[2] += p[2]
            out += bytes(v // (ss * ss) for v in acc)
    return bytes(out)

def png(path, size):
    raw = render(size)
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)

png(sys.argv[1], int(sys.argv[2]))

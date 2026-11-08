#!/usr/bin/env python3
"""生成 1024×1024 应用图标（深色底 + 青色电源环 + 闪电）。

仓库里不放二进制，CI 上现算：图标完全由这点数学决定，每次结果一致。
本地想换配色改下面的 cyan / 背景系数即可。
"""

import os
import struct
import zlib

import numpy as np

S = 2048
c = S / 2.0
y, x = np.mgrid[0:S, 0:S].astype(np.float32)
dx = x - c
dy = y - c
r = np.sqrt(dx * dx + dy * dy)
s = S / 1024.0

# 背景：近黑到深蓝的对角渐变
t = (x + y) / (2.0 * S)
img = np.zeros((S, S, 3), np.float32)
img[..., 0] = 0.035 + 0.030 * t
img[..., 1] = 0.048 + 0.055 * t
img[..., 2] = 0.075 + 0.080 * t

# 环后方辉光
glow = np.exp(-((r - 330 * s) ** 2) / (2 * (140 * s) ** 2)) * 0.30
img += glow[..., None] * np.array([0.05, 0.34, 0.42], np.float32)

# 电源环，顶部留 9° 缺口
ring = np.abs(r - 330 * s) < 20 * s
ang = np.degrees(np.arctan2(dx, -dy))
ring &= ~(np.abs(ang) < 9.0)
stem = (np.abs(dx) < 21 * s) & (dy > -347 * s) & (dy < -205 * s)

cyan = np.array([0.22, 0.85, 0.96], np.float32)
mask = (ring | stem).astype(np.float32)
img = img * (1 - mask[..., None]) + cyan * mask[..., None]

# 闪电多边形
pts = [(8, -172), (108, -172), (30, -26), (104, -26), (-38, 190), (4, 8), (-74, 12)]
pts = [(px * s * 0.94, py * s * 0.94) for px, py in pts]
poly = np.zeros((S, S), bool)
n = len(pts)
j = n - 1
X, Y = dx, dy
for i in range(n):
    xi, yi = pts[i]
    xj, yj = pts[j]
    cond = ((yi > Y) != (yj > Y)) & (X < (xj - xi) * (Y - yi) / (yj - yi + 1e-9) + xi)
    poly ^= cond
    j = i

white = np.array([0.95, 0.998, 1.0], np.float32)
img = img * (1 - poly[..., None]) + white * poly[..., None]

img = img.reshape(1024, 2, 1024, 2, 3).mean(axis=(1, 3))
arr = np.clip(img * 255.0, 0, 255).astype(np.uint8)


def chunk(tag, data):
    body = tag + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)


h, w, _ = arr.shape
raw = b''.join(b'\x00' + arr[i].tobytes() for i in range(h))
png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw, 9))
png += chunk(b'IEND', b'')

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, 'ESP32WOL', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(png)
print('icon ->', out, len(png), 'bytes')

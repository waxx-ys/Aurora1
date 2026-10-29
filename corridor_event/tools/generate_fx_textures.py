#!/usr/bin/env python3
"""generate_fx_textures.py · 生成氛围用的小贴图（可重复执行）

会生成：
    assets/fx/fog_mist.png   贴地雾/雾帘用的软噪声图
    assets/fx/card_back.png  女巫牌阵浮空卡牌的卡背
    assets/fx/talisman.png   墙上符纸
    assets/fx/rag_cloth.png  横梁破布

依赖：Python 3 + Pillow。macOS 上可用 DSH 自带 Python 或系统 Python：
    python3 tools/generate_fx_textures.py
如果系统没有 Pillow：
    /Applications/DeepSeek\\ Harness.app/... 这里不写死路径，
    在 DSH 环境里直接运行本脚本通常已带 Pillow。

生成后如需 Godot 重新导入：
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path . --import
"""

from __future__ import annotations

import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fx"
OUT.mkdir(parents=True, exist_ok=True)


def make_fog_mist() -> None:
    size = 256
    random.seed(13)
    noise = Image.new("L", (size, size))
    px = noise.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = random.randint(0, 255)
    noise = noise.filter(ImageFilter.GaussianBlur(14))

    noise2 = Image.new("L", (size, size))
    px = noise2.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = random.randint(0, 255)
    noise2 = noise2.filter(ImageFilter.GaussianBlur(5))

    mask = Image.new("L", (size, size))
    mp = mask.load()
    for y in range(size):
        for x in range(size):
            nx = (x - size / 2) / (size / 2)
            ny = (y - size / 2) / (size / 2)
            radial = max(0.0, 1.0 - math.sqrt(nx * nx + ny * ny)) ** 1.6
            value = noise.getpixel((x, y)) * 0.72 + noise2.getpixel((x, y)) * 0.28
            mp[x, y] = int(max(0, min(255, value * radial * 1.5)))
    fog = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    fog.putalpha(mask)
    fog.save(OUT / "fog_mist.png")


def make_card_back() -> None:
    width, height = 256, 384
    card = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    for y in range(height):
        t = y / height
        draw.line([(0, y), (width, y)], fill=(int(18 + 8 * t), int(10 + 4 * t), int(28 + 10 * t), 255))
    draw.rounded_rectangle([10, 10, width - 10, height - 10], radius=14, outline=(116, 84, 148, 255), width=2)
    draw.rounded_rectangle([20, 20, width - 20, height - 20], radius=10, outline=(96, 80, 140, 220), width=1)
    for cx, cy in [(34, 34), (width - 34, 34), (34, height - 34), (width - 34, height - 34)]:
        draw.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], outline=(190, 170, 230, 200), width=1)
        draw.line([(cx - 4, cy), (cx + 4, cy)], fill=(190, 170, 230, 200), width=1)
        draw.line([(cx, cy - 4), (cx, cy + 4)], fill=(190, 170, 230, 200), width=1)
    cx, cy = width // 2, height // 2
    draw.ellipse([cx - 62, cy - 62, cx + 62, cy + 62], outline=(110, 86, 150, 190), width=2)
    draw.ellipse([cx - 48, cy - 48, cx + 48, cy + 48], outline=(110, 90, 160, 160), width=1)
    draw.ellipse([cx - 34, cy - 46, cx + 34, cy + 22], fill=(8, 6, 14, 255))
    draw.ellipse([cx - 18, cy - 50, cx + 44, cy + 10], fill=(22, 13, 34, 255))
    draw.ellipse([cx - 30, cy - 12, cx + 30, cy + 22], outline=(178, 150, 240, 230), width=2)
    draw.ellipse([cx - 12, cy - 3, cx + 12, cy + 21], fill=(130, 100, 200, 255))
    draw.ellipse([cx - 4, cy + 4, cx + 4, cy + 12], fill=(10, 20, 12, 255))
    for k in range(7):
        y = 70 + k * 34
        if abs(y - cy) < 56:
            continue
        draw.line([(width // 2 - 26, y), (width // 2 + 26, y)], fill=(120, 108, 160, 120), width=1)
        draw.line([(width // 2, y - 8), (width // 2, y + 8)], fill=(150, 132, 200, 150), width=1)
    for k in range(3):
        draw.line([(width // 2 - 30 + k * 22, height - 54), (width // 2 - 18 + k * 22, height - 40)],
                  fill=(190, 172, 230, 160), width=1)
    draw.line([(width // 2 - 26, height - 32), (width // 2 + 26, height - 32)], fill=(110, 90, 140, 180), width=1)
    card.filter(ImageFilter.GaussianBlur(0.4)).save(OUT / "card_back.png")


def make_talisman() -> None:
    width, height = 128, 256
    talisman = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(talisman)
    points = [(18, 8), (112, 12), (118, 60), (112, 118), (120, 190), (108, 244), (34, 248), (20, 196), (12, 128), (16, 70)]
    draw.polygon(points, fill=(74, 72, 48, 255), outline=(28, 30, 20, 255))
    draw.line(points + [points[0]], fill=(26, 28, 20, 255), width=2)
    draw.rounded_rectangle([30, 26, 100, 228], radius=4, outline=(160, 140, 96, 190), width=1)
    random.seed(7)
    for k in range(9):
        y = 38 + k * 21
        w = random.choice([10, 16, 22])
        draw.line([(64, y), (64 + random.choice([-w, w]), y + 12)], fill=(224, 202, 130, 220), width=2)
        draw.line([(64 + random.choice([-8, 8]), y + 2), (64 + random.choice([-8, 8]), y + 14)],
                  fill=(224, 202, 130, 200), width=1)
    draw.line([(40, 222), (88, 222)], fill=(170, 90, 80, 200), width=2)
    talisman.save(OUT / "talisman.png")


def make_rag_cloth() -> None:
    width, height = 128, 256
    random.seed(23)
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    points = []
    for i in range(24):
        angle = 2 * math.pi * i / 24
        radius = 0.42 + 0.06 * math.sin(angle * 5) + random.uniform(-0.03, 0.03)
        points.append((width / 2 + math.cos(angle) * width * radius,
                       height / 2 + math.sin(angle) * height * radius * 0.55))
    draw.polygon(points, fill=(62, 56, 48, 255), outline=(28, 25, 22, 255))
    for k in range(7):
        x = 22 + k * 13
        draw.line([(x, height * 0.82), (x + random.randint(-5, 5), height - 8)], fill=(52, 47, 40, 255), width=3)
    for _ in range(5):
        hx, hy = random.randint(28, 100), random.randint(40, 200)
        hr = random.randint(3, 9)
        draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(0, 0, 0, 0))
    for _ in range(18):
        x, y = random.randint(20, 108), random.randint(30, 220)
        draw.ellipse([x - 6, y - 4, x + 6, y + 4], fill=(38, 34, 28, 120))
    draw.line([(36, 36), (36, 72)], fill=(92, 80, 62, 180), width=1)
    draw.line([(92, 48), (92, 90)], fill=(92, 80, 62, 180), width=1)
    image.save(OUT / "rag_cloth.png")


def main() -> None:
    make_fog_mist()
    make_card_back()
    make_talisman()
    make_rag_cloth()
    for name in ("fog_mist", "card_back", "talisman", "rag_cloth"):
        print(f"generated: assets/fx/{name}.png")


if __name__ == "__main__":
    main()

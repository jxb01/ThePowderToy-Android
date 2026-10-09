#!/usr/bin/env python3
"""从 The Powder Toy 的 icon_exe.png 生成 Android 启动图标。

产出：
  app/src/main/res/mipmap-<density>/ic_launcher.png        各密度方形图标
  app/src/main/res/mipmap-<density>/ic_launcher_round.png  各密度圆形图标
  app/src/main/res/drawable/ic_launcher_foreground.png     自适应图标前景（108dp @ xxxhdpi）
  app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml       自适应图标（Android 8+）
  app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml

用法：
    python scripts/make-icons.py [源 png]
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
RES = os.path.join(PROJECT, "app", "src", "main", "res")

DEFAULT_SRC = r"C:\Users\JG\Downloads\The-Powder-Toy\resources\generated_icons\icon_exe.png"

# 自适应图标：108dp 画布里有 18dp 的安全边距，实际可见区是中间 72dp
ADAPTIVE_CANVAS = 432          # 108dp @ xxxhdpi
ADAPTIVE_ICON = 300            # 图标占画布的比例，留出被裁成圆形/水滴形的余量

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
	<background android:drawable="@color/ic_launcher_background" />
	<foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""


def circular(img):
    """把方形图标裁成圆形；先在 4 倍尺寸上画圆再缩回来，边缘才平滑。"""
    size = img.size[0]
    big = size * 4
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def fit_square(img, box):
    """等比缩放并居中到 box 的正方形里。"""
    out = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    w, h = img.size
    scale = min(box / w, box / h)
    new = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    out.paste(new, ((box - new.size[0]) // 2, (box - new.size[1]) // 2), new)
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.isfile(src):
        print("找不到源图标: " + src, file=sys.stderr)
        return 1

    base = Image.open(src).convert("RGBA")
    print("源图标: {} {}".format(src, base.size))

    for density, size in DENSITIES.items():
        d = os.path.join(RES, "mipmap-" + density)
        os.makedirs(d, exist_ok=True)
        square = fit_square(base, size)
        square.save(os.path.join(d, "ic_launcher.png"))
        circular(square).save(os.path.join(d, "ic_launcher_round.png"))
        print("  mipmap-{:<8} {:>3}px".format(density, size))

    drawable = os.path.join(RES, "drawable")
    os.makedirs(drawable, exist_ok=True)
    fg = Image.new("RGBA", (ADAPTIVE_CANVAS, ADAPTIVE_CANVAS), (0, 0, 0, 0))
    icon = fit_square(base, ADAPTIVE_ICON)
    off = (ADAPTIVE_CANVAS - ADAPTIVE_ICON) // 2
    fg.paste(icon, (off, off), icon)
    fg.save(os.path.join(drawable, "ic_launcher_foreground.png"))
    print("  drawable/ic_launcher_foreground.png {}px".format(ADAPTIVE_CANVAS))

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as f:
            f.write(ADAPTIVE_XML)
    print("  mipmap-anydpi-v26/ic_launcher{,_round}.xml")
    return 0


if __name__ == "__main__":
    sys.exit(main())

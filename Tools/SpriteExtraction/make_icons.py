#!/usr/bin/env python3
"""
Builds the macOS app icon set and the menu bar template icon from the supplied art.

  * AppIcon: the supplied 1254px icon sits on solid black. The black surround is
    turned into transparency (soft edge kept) and the result is exported at every
    size macOS asks for.
  * MenuBarIcon: a monochrome template of Whiskumi's head cut from the idle sprite,
    with eyes and inner ears knocked out, at 1x/2x/3x. macOS tints template images for
    light and dark menu bars automatically.

Run after extract_sprites.py (it reads the extracted idle frame).
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(REPO, "Whiskumi", "Whiskumi", "Assets.xcassets")
ANIM = os.path.join(REPO, "Whiskumi", "Whiskumi", "Resources", "CatAnimations")


def app_icon():
    src = np.array(Image.open(os.path.join(HERE, "source", "app_icon.png")).convert("RGB")).astype(float)
    brightness = src.max(axis=2)
    # the icon body is never darker than ~35; the surround is pure black
    alpha = np.clip((brightness - 6) / 26.0, 0, 1)
    rgba = np.dstack([src, alpha * 255]).astype(np.uint8)
    im = Image.fromarray(rgba)
    ys, xs = np.nonzero(alpha > 0.5)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    body = im.crop((x0, y0, x1, y1))
    # Apple's grid: the rounded square is 824pt inside a 1024pt canvas
    side = 1024
    inner = 824
    body = body.resize((inner, round(inner * body.height / body.width)), Image.LANCZOS)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(body, ((side - body.width) // 2, (side - body.height) // 2))

    out = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            canvas.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
            images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}", "filename": name})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
              open(os.path.join(out, "Contents.json"), "w"), indent=2)


def menu_bar_icon():
    """Template icon: Whiskumi's head (ears, eyes, nose) cut from the first idle frame."""
    from scipy import ndimage as ndi
    manifest = json.load(open(os.path.join(ANIM, "CatAnimations.json")))
    idle = manifest["animations"]["idle"]
    frame = np.array(Image.open(os.path.join(ANIM, "Idle", "idle_00.png")).convert("RGBA")).astype(int)
    a = frame[:, :, 3] > 0
    ys, xs = np.nonzero(a)
    top = ys.min()
    head_x = idle["anchor"][0]
    half_w = 44
    chin = top + 66
    crop = frame[top:chin, int(head_x - half_w):int(head_x + half_w)]
    a = crop[:, :, 3] > 0
    lum = crop[:, :, :3].mean(axis=2)
    interior = ndi.binary_erosion(a, iterations=7)
    holes = ndi.binary_dilation(interior & (lum < 120), iterations=1) & interior
    pinkish = interior & (crop[:, :, 0] - crop[:, :, 1] > 40)
    shape = a & ~holes & ~pinkish
    ys, xs = np.nonzero(shape)
    shape = shape[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    out = os.path.join(ASSETS, "MenuBarIcon.imageset")
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))
    images = []
    for scale in (1, 2, 3):
        h = 15 * scale
        w = round(shape.shape[1] * h / shape.shape[0])
        m = Image.fromarray((shape * 255).astype(np.uint8)).resize((w, h), Image.BOX)
        m = np.where(np.array(m) > 120, 255, 0).astype(np.uint8)
        rgba = np.zeros((h, w, 4), dtype=np.uint8)
        rgba[:, :, 3] = m
        name = f"menubar_{scale}x.png"
        Image.fromarray(rgba).save(os.path.join(out, name))
        images.append({"idiom": "universal", "scale": f"{scale}x", "filename": name})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1},
               "properties": {"template-rendering-intent": "template"}},
              open(os.path.join(out, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    app_icon()
    menu_bar_icon()
    print("icons written")

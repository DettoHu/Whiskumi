#!/usr/bin/env python3
"""
Extracts Whiskumi's animation frames from the supplied sprite sheets.

Usage (from the repository root):
    python3 -m venv .venv && .venv/bin/pip install pillow numpy scipy
    .venv/bin/python Tools/SpriteExtraction/extract_sprites.py

What it does:
  * reads sprite_spec.json (hand-mapped frame rectangles for every animation),
  * keeps only the cat's own connected components inside each rectangle, which
    drops the grey label pills, drawn cursors, and effect marks,
  * lifts effects (hearts, Zs, "?", the ball...) out as separate prop sprites,
  * normalises the two sheets to the same cat size (the activities sheet is drawn
    smaller), using premultiplied-alpha Lanczos so edges do not get halos,
  * hardens alpha so the pixel art has crisp edges on any desktop wallpaper,
  * aligns frames inside an animation so the cat does not jitter,
  * writes PNG frames plus CatAnimations.json into the app's resources.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "Whiskumi", "Whiskumi", "Resources", "CatAnimations")

LABEL_ALPHA = 90      # alpha above which a pixel counts as "ink" for segmentation
HARD_ALPHA = 110      # alpha threshold used when hardening edges
MIN_COMPONENT = 12    # ignore specks of compression noise
PAD = 2               # transparent padding around every canvas


def load_sheet(path):
    return np.array(Image.open(os.path.join(HERE, path)).convert("RGBA"))


def rect_mask(shape, rect):
    m = np.zeros(shape[:2], dtype=bool)
    x0, y0, x1, y1 = rect
    m[y0:y1, x0:x1] = True
    return m


class Sheet:
    def __init__(self, path, scale):
        self.rgba = load_sheet(path)
        self.scale = scale
        ink = self.rgba[:, :, 3] > LABEL_ALPHA
        self.labels, _ = ndi.label(ink, structure=np.ones((3, 3)))
        self.objects = ndi.find_objects(self.labels)

    def components_inside(self, rect, excludes=()):
        """Component ids whose bounding box lies fully inside rect (+1px slack)."""
        x0, y0, x1, y1 = rect
        ids = []
        for idx, sl in enumerate(self.objects):
            if sl is None:
                continue
            ys, xs = sl
            if xs.start >= x0 - 1 and xs.stop <= x1 + 1 and ys.start >= y0 - 1 and ys.stop <= y1 + 1:
                area = int((self.labels[sl] == idx + 1).sum())
                if area < MIN_COMPONENT:
                    continue
                excluded = False
                for ex in excludes:
                    ex0, ey0, ex1, ey1 = ex
                    if xs.start >= ex0 - 1 and xs.stop <= ex1 + 1 and ys.start >= ey0 - 1 and ys.stop <= ey1 + 1:
                        excluded = True
                if not excluded:
                    ids.append(idx + 1)
        return ids

    def cutout(self, rect, excludes=()):
        """Returns (rgba crop, top-left in sheet space) containing only the selected components."""
        ids = self.components_inside(rect, excludes)
        if not ids:
            raise ValueError(f"no components inside {rect}")
        keep = np.isin(self.labels, ids)
        # grow by one pixel so anti-aliased outline pixels just under the ink threshold survive
        keep = ndi.binary_dilation(keep, structure=np.ones((3, 3)))
        ys, xs = np.nonzero(keep)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        crop = self.rgba[y0:y1, x0:x1].copy()
        crop[~keep[y0:y1, x0:x1]] = 0
        return crop, (int(x0), int(y0))


def rescale(rgba, scale):
    if abs(scale - 1.0) < 1e-6:
        return rgba
    im = Image.fromarray(rgba).convert("RGBa")  # premultiplied to avoid dark/white fringes
    w, h = im.size
    im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    return np.array(im.convert("RGBA"))


def harden(rgba):
    out = rgba.copy()
    a = out[:, :, 3]
    solid = a >= HARD_ALPHA
    out[:, :, 3] = np.where(solid, 255, 0).astype(np.uint8)
    out[~solid] = 0
    return out


def head_x(rgba):
    """Horizontal centre of the head, found from the pink inner ears in the upper part of the sprite."""
    a = rgba.astype(int)
    alpha = a[:, :, 3] > 128
    ys = np.nonzero(alpha)[0]
    if len(ys) == 0:
        return rgba.shape[1] / 2
    top, bottom = ys.min(), ys.max()
    limit = top + int((bottom - top) * 0.55)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    pink = alpha & (r > 200) & (g < 195) & (b < 205) & (r - g > 35)
    pink[limit:, :] = False
    lab, n = ndi.label(pink)
    blobs = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        size = int((lab[sl] == i + 1).sum())
        if size >= 15:
            blobs.append((sl[0].start, ndi.center_of_mass(pink, lab, i + 1)[1]))
    if not blobs:
        cols = np.nonzero(alpha)[1]
        return float(cols.mean())
    # the ears are the highest pink blobs; heart eyes, blush and noses sit lower
    blobs.sort()
    return float(np.mean([b[1] for b in blobs[:2]]))


def best_shift(ref_mask, mask, ref_left, left, search=24):
    """dx (added to `left`) that maximises mask overlap with the reference, both bottom aligned."""
    h = max(ref_mask.shape[0], mask.shape[0])
    width = max(ref_left + ref_mask.shape[1], left + mask.shape[1]) + 2 * search + 4
    base = np.zeros((h, width), dtype=bool)
    base[h - ref_mask.shape[0]:, search + ref_left: search + ref_left + ref_mask.shape[1]] = ref_mask
    best, best_dx = -1.0, 0
    for dx in range(-search, search + 1):
        cand = np.zeros_like(base)
        x = search + left + dx
        if x < 0 or x + mask.shape[1] > width:
            continue
        cand[h - mask.shape[0]:, x:x + mask.shape[1]] = mask
        inter = np.logical_and(base, cand).sum()
        union = np.logical_or(base, cand).sum()
        score = inter / union if union else 0
        if score > best:
            best, best_dx = score, dx
    return best_dx


def build():
    spec = json.load(open(os.path.join(HERE, "sprite_spec.json")))
    sheets = {k: Sheet(v["file"], v["scale"]) for k, v in spec["sheets"].items()}
    os.makedirs(OUT_DIR, exist_ok=True)
    for f in os.listdir(OUT_DIR):
        if f.endswith(".png") or f.endswith(".json"):
            os.remove(os.path.join(OUT_DIR, f))
    for d in os.listdir(OUT_DIR):
        p = os.path.join(OUT_DIR, d)
        if os.path.isdir(p):
            for f in os.listdir(p):
                if f.endswith(".png"):
                    os.remove(os.path.join(p, f))

    manifest = {"version": 1, "animations": {}, "props": {}}

    # --- props -----------------------------------------------------------------
    prop_dir = os.path.join(OUT_DIR, "Props")
    os.makedirs(prop_dir, exist_ok=True)
    for name, p in spec["props"].items():
        sheet = sheets[p["sheet"]]
        crop, _ = sheet.cutout(p["rect"])
        img = harden(rescale(crop, sheet.scale))
        img = np.pad(img, ((1, 1), (1, 1), (0, 0)))
        file = f"prop_{name}"
        Image.fromarray(img).save(os.path.join(prop_dir, file + ".png"))
        manifest["props"][name] = {"image": file, "size": [img.shape[1], img.shape[0]]}

    # --- animations ------------------------------------------------------------
    for name, a in spec["animations"].items():
        sheet = sheets[a["sheet"]]
        s = sheet.scale
        excludes = a.get("exclude", [])
        raw = []
        for rect in a["frames"]:
            crop, origin = sheet.cutout(rect, excludes)
            raw.append((crop, origin))
        baseline_src = a.get("baseline", max(o[1] + c.shape[0] for c, o in raw))

        frames = []  # (hardened rgba, left, top) in scaled space relative to frame-0 left / baseline
        for crop, (ox, oy) in raw:
            img = harden(rescale(crop, s))
            top = round((oy - baseline_src) * s)   # negative: pixels above baseline
            frames.append([img, 0, top])

        # horizontal alignment
        if a["align"] == "head":
            hx0 = head_x(frames[0][0])
            for f in frames:
                f[1] = round(hx0 - head_x(f[0]))
        else:
            ref = frames[0][0][:, :, 3] > 0
            for f in frames[1:]:
                m = f[0][:, :, 3] > 0
                # start from centred placement, then refine
                left = round((ref.shape[1] - m.shape[1]) / 2)
                f[1] = left + best_shift(ref, m, 0, left)

        min_left = min(f[1] for f in frames)
        max_right = max(f[1] + f[0].shape[1] for f in frames)
        min_top = min(f[2] for f in frames)
        max_bottom = max(f[2] + f[0].shape[0] for f in frames)
        cw = max_right - min_left + 2 * PAD
        ch = max_bottom - min_top + 2 * PAD
        anim_dir = os.path.join(OUT_DIR, name[0].upper() + name[1:])
        os.makedirs(anim_dir, exist_ok=True)
        names = []
        frame_offsets = []
        for i, (img, left, top) in enumerate(frames):
            canvas = np.zeros((ch, cw, 4), dtype=np.uint8)
            x = left - min_left + PAD
            y = top - min_top + PAD
            canvas[y:y + img.shape[0], x:x + img.shape[1]] = img
            file = f"{name}_{i:02d}"
            Image.fromarray(canvas).save(os.path.join(anim_dir, file + ".png"))
            names.append(file)
            frame_offsets.append((x, y))

        # anchor: head centre of frame 0 horizontally, ground line vertically
        anchor_x = frame_offsets[0][0] + head_x(frames[0][0])
        anchor_y = -min_top + PAD  # baseline row in canvas space
        entry = {
            "frames": names,
            "size": [cw, ch],
            "anchor": [round(anchor_x, 1), anchor_y],
            "facing": a.get("facing", "right"),
        }

        # emote / per-frame prop placements, relative to the canvas of the frame they belong to
        def place(items):
            placed = []
            for e in items:
                fi = e.get("frame", 0)
                crop_ox, crop_oy = raw[fi][1]
                fx, fy = frame_offsets[fi]
                _, (ex0, ey0) = sheet.cutout(e["rect"])
                # the prop PNG has a 1px transparent pad, hence the -1
                px = fx + round((ex0 - crop_ox) * s) - 1
                py = fy + round((ey0 - crop_oy) * s) - 1
                placed.append({"prop": e["prop"], "frame": fi, "x": px, "y": py})
            return placed

        if "emotes" in a:
            entry["emotes"] = place(a["emotes"])
        if "frameProps" in a:
            entry["frameProps"] = place(a["frameProps"])
        manifest["animations"][name] = entry
        print(f"{name:11s} frames={len(names)} canvas={cw}x{ch} anchor=({anchor_x:.0f},{anchor_y})")

    with open(os.path.join(OUT_DIR, "CatAnimations.json"), "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    sys.exit(build())

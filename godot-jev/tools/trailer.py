# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Cuts a 1920x1080 trailer from a 2560x1440 session recording, using the marks in its log.

    uv run tools/trailer.py session.avi session.log trailer.mp4

Two beats (the gin line comes back unknown, the skeleton line acts), with captions,
eased zooms on the input, spotlights on the results, and an end card. Needs ffmpeg.
"""
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SRC, LOG, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FONTS = str(Path(__file__).resolve().parent.parent / "demo" / "fonts") + "/"
FPS = 30
SW, SH = 2560, 1440
OW, OH = 1920, 1080
TYPING_SPEEDUP = 1.7
READ_ZOOMED, ZOOM_OUT, HOLD_WIDE = 24, 27, 66  # frames on the skeleton beat's answer

BG = (11, 9, 16)
INK = (232, 220, 192)
GOLD = (240, 184, 90)
DIM = (141, 130, 163)

FULL = (0.0, 0.0, SW, SH)
INPUT = (1370.0, 751.0, 1180.0, 1180.0 * 9 / 16)  # the input line and the answer above it
TOP_OF_LOG = (1370.0, 110.0, 1180.0, 1180.0 * 9 / 16)  # the first answers, before the log fills

# Spotlit areas, in source pixels.
GIN_EXCHANGE = (1405, 490, 2380, 602)
BONES_EXCHANGE = (1405, 1092, 2505, 1300)
JEV_PANEL = (636, 858, 1356, 1100)

GIN = "ayo where the gin and juice at, nephew?"
BONES = "lay the smack down on Mr. Bones wit the blade"


def marks():
    found = {}
    for line in open(LOG):
        m = re.match(r"mark (\d+) (\w+) (.*)", line.strip())
        if m:
            found.setdefault((m.group(2), m.group(3)), int(m.group(1)))
    return found


M = marks()


def seg(name, start, end, rate=1.0):
    n = int(round((end - start) / rate))
    return {"name": name, "src": [start + int(round(k * rate)) for k in range(n)]}


g_t, g_e, g_s = M["typing", GIN], M["enter", GIN], M["shown", GIN]
b_t, b_e, b_s = M["typing", BONES], M["enter", BONES], M["shown", BONES]

segments = [
    seg("intro", g_t - 15, g_t),
    seg("gin_typing", g_t, g_e, TYPING_SPEEDUP),
    seg("gin_answer", g_e, g_s + 75),
    seg("hall", b_t - 24, b_t),
    seg("bones_typing", b_t, b_e, TYPING_SPEEDUP),
    seg("bones_answer", b_e, b_s + READ_ZOOMED + ZOOM_OUT + HOLD_WIDE),
]
END_CARD = 54

# Output frame index where each segment starts.
starts, total = {}, 0
for s in segments:
    starts[s["name"]] = total
    total += len(s["src"])
starts["end"] = total
total += END_CARD
src_of = [f for s in segments for f in s["src"]]


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def lerp_rect(a, b, x):
    return tuple(p + (q - p) * ease(x) for p, q in zip(a, b))


bones_shown = starts["bones_answer"] + (b_s - b_e)
gin_panned = starts["gin_answer"] + 3 + 22

# (output frame, rect) keyframes; each move eases from the previous keyframe.
ZOOM = 24
keys = [
    (0, FULL),
    (6, FULL),
    (6 + ZOOM, INPUT),
    (starts["gin_answer"] + 3, INPUT),
    (gin_panned, TOP_OF_LOG),
    (starts["hall"] - 1, TOP_OF_LOG),
    (starts["hall"], FULL),
    (starts["hall"] + 16, FULL),
    (starts["hall"] + 16 + ZOOM, INPUT),
    (bones_shown + READ_ZOOMED, INPUT),
    (bones_shown + READ_ZOOMED + ZOOM_OUT, FULL),
]


def camera(i):
    for (f0, r0), (f1, r1) in zip(keys, keys[1:]):
        if f0 <= i <= f1:
            return r0 if f1 == f0 else lerp_rect(r0, r1, (i - f0) / (f1 - f0))
    return keys[-1][1]


captions = [
    (0, starts["gin_answer"] + 8, "Players type anything."),
    (starts["gin_answer"] + 10, starts["hall"] + 8, "Ask for what the author never wrote: nothing happens."),
    (starts["hall"] + 10, starts["bones_answer"] + 8, "Say it your way..."),
    (starts["bones_answer"] + 12, starts["end"], "...and Jev picks the move the author wrote."),
]

spots = [
    (gin_panned - 4, starts["hall"] - 2, GIN_EXCHANGE),
    (bones_shown - 2, bones_shown + READ_ZOOMED + 4, BONES_EXCHANGE),
    (bones_shown + READ_ZOOMED + ZOOM_OUT - 6, starts["end"] + 4, JEV_PANEL),
]


def draw_spots(img, i):
    """Dims everything but the spotlit area and rings it in gold, following the camera."""
    x, y, w, h = camera(i)
    for a, b, (x0, y0, x1, y1) in spots:
        alpha = fade(i, a, b, 8)
        if alpha <= 0:
            continue
        pad = 12
        box = [(x0 - x) / w * OW - pad, (y0 - y) / h * OH - pad, (x1 - x) / w * OW + pad, (y1 - y) / h * OH + pad]
        layer = Image.new("RGBA", (OW, OH), (0, 0, 0, int(95 * alpha)))
        d = ImageDraw.Draw(layer)
        d.rounded_rectangle(box, radius=14, fill=(0, 0, 0, 0))
        d.rounded_rectangle(box, radius=14, outline=GOLD + (int(210 * alpha),), width=3)
        img.alpha_composite(layer)


caption_font = ImageFont.truetype(FONTS + "PixelifySans.ttf", 50)
title_font = ImageFont.truetype(FONTS + "PixelifySans.ttf", 120)
line_font = ImageFont.truetype(FONTS + "VT323-Regular.ttf", 58)
small_font = ImageFont.truetype(FONTS + "VT323-Regular.ttf", 44)


def fade(i, a, b, n=6):
    return min(1.0, (i - a) / n, (b - i) / n) if a <= i < b else 0.0


def draw_caption(img, i):
    for a, b, text in captions:
        alpha = fade(i, a, b)
        if alpha <= 0:
            continue
        band = Image.new("RGBA", (OW, 116), BG + (int(215 * alpha),))
        d = ImageDraw.Draw(band)
        d.text((OW / 2, 58), text, font=caption_font, fill=INK + (int(255 * alpha),), anchor="mm")
        img.alpha_composite(band, (0, 0))


def draw_end_card(img, k):
    shade = Image.new("RGBA", (OW, OH), BG + (int(225 * ease(k / 12)),))
    img.alpha_composite(shade)
    alpha = ease((k - 6) / 12)
    layer = Image.new("RGBA", (OW, OH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a = int(255 * alpha)
    d.text((OW / 2, 420), "The Sunken Crypt", font=title_font, fill=GOLD + (a,), anchor="mm")
    d.text((OW / 2, 560), "Type anything. Only what the author wrote can happen.", font=line_font, fill=INK + (a,), anchor="mm")
    d.text((OW / 2, 650), "a parser game powered by Jev", font=small_font, fill=DIM + (a,), anchor="mm")
    img.alpha_composite(layer)


def frames_from(first):
    """Source frames from `first` on, in order, as PIL images."""
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-ss", f"{first / FPS:.4f}", "-i", SRC, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE,
    )
    n = first
    try:
        while True:
            raw = proc.stdout.read(SW * SH * 3)
            if len(raw) < SW * SH * 3:
                break
            yield n, Image.frombytes("RGB", (SW, SH), raw)
            n += 1
    finally:
        proc.kill()


out = subprocess.Popen(
    ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{OW}x{OH}", "-r", str(FPS), "-i", "-",
     "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart", OUT],
    stdin=subprocess.PIPE,
)

current = None
last = None
for i in range(total):
    if i < len(src_of):
        want = src_of[i]
        if current is None or want < current[0] or want - current[0] > 90:
            if current is not None:
                reader.close()
            reader = frames_from(want)
            current = next(reader)
        while current[0] < want:
            current = next(reader)
        x, y, w, h = camera(i)
        last = current[1].resize((OW, OH), resample=Image.LANCZOS, box=(x, y, x + w, y + h)).convert("RGBA")
        img = last.copy()
        if i == starts["hall"] - 1:
            before_cut = img.copy()
        dissolve = (i - starts["hall"] + 1) / 7
        if 0 < dissolve < 1:
            img = Image.blend(before_cut, img, ease(dissolve))
    else:
        img = last.copy()
        draw_end_card(img, i - starts["end"])
    if i < starts["end"]:
        draw_spots(img, i)
    draw_caption(img, i)
    out.stdin.write(img.convert("RGB").tobytes())

out.stdin.close()
out.wait()
print(f"{total} frames, {total / FPS:.1f} s; segments start at", {k: round(v / FPS, 2) for k, v in starts.items()})

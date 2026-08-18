#!/usr/bin/env python3
"""
Draws DiagClean.app's icon and builds AppIcon.icns.

The icon is generated from this script rather than committed as an opaque binary, so
it can be reviewed, adjusted and reproduced like the rest of the app. Run it after
changing anything here:

    python3 Scripts/make-icon.py

Design follows the app: a dark, low-glare squircle with one accent colour. A ring with
a pulse through it — the same "is this machine healthy" idea the Status section leads
with — rather than the brooms and rockets that cleanup utilities usually reach for.
"""
import os
import subprocess
import sys
from PIL import Image, ImageDraw

# Drawn at 4x and downsampled, which is cheaper than fighting PIL for antialiasing.
SCALE = 4
SIZE = 1024 * SCALE

BACKGROUND_TOP = (35, 42, 46)
BACKGROUND_BOTTOM = (20, 24, 27)
ACCENT = (92, 173, 191)
ACCENT_BRIGHT = (140, 205, 219)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")


def squircle_mask(size, radius):
    """macOS's rounded-rect silhouette. A plain rounded rectangle is close enough at
    icon sizes that the difference is invisible once the OS masks it anyway."""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        gradient.putpixel((0, y), tuple(
            int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return gradient.resize((size, size))


def draw_icon(compact=False):
    # Big Sur proportions: the artwork occupies ~82% of the canvas, the rest is the
    # breathing room macOS expects around every icon.
    inset = int(SIZE * 0.098)
    body = SIZE - inset * 2
    radius = int(body * 0.225)

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    plate = vertical_gradient(body, BACKGROUND_TOP, BACKGROUND_BOTTOM).convert("RGBA")
    plate.putalpha(squircle_mask(body, radius))
    canvas.paste(plate, (inset, inset), plate)

    draw = ImageDraw.Draw(canvas)
    centre = SIZE // 2
    ring_radius = int(body * 0.30)
    ring_width = int(body * 0.052)

    # The ring is dropped entirely below 32px. Downsampling the full design that far
    # merges the ring and the pulse into an unreadable smudge, so the small sizes get a
    # bolder, simpler mark instead — which is what Apple's own icons do rather than
    # shrinking one drawing all the way down.
    if not compact:
        # Broken on the left and right so the pulse reads as passing through the ring
        # rather than sitting on top of it.
        draw.arc(
            [centre - ring_radius, centre - ring_radius, centre + ring_radius, centre + ring_radius],
            start=200, end=340, fill=ACCENT, width=ring_width,
        )
        draw.arc(
            [centre - ring_radius, centre - ring_radius, centre + ring_radius, centre + ring_radius],
            start=20, end=160, fill=ACCENT, width=ring_width,
        )

    # An ECG trace: flat, a small dip, the tall spike, then flat again.
    span = int(body * (0.42 if compact else 0.36))
    unit = span / 4.0
    points = [
        (centre - span, centre),
        (centre - unit * 1.7, centre),
        (centre - unit * 1.05, centre + int(body * 0.075)),
        (centre - unit * 0.35, centre - int(body * 0.175)),
        (centre + unit * 0.35, centre + int(body * 0.105)),
        (centre + unit * 1.0, centre),
        (centre + span, centre),
    ]
    draw.line(
        points, fill=ACCENT_BRIGHT,
        width=int(body * (0.085 if compact else 0.055)), joint="curve",
    )

    # A soft highlight along the top edge, which is what stops a flat dark icon looking
    # like a hole punched in the Dock. Skipped when compact: a sub-pixel outline at 16px
    # is just noise.
    if compact:
        return canvas.resize((1024, 1024), Image.LANCZOS)

    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(highlight).rounded_rectangle(
        [inset, inset, SIZE - inset - 1, SIZE - inset - 1],
        radius=radius, outline=(255, 255, 255, 28), width=int(body * 0.006),
    )
    canvas = Image.alpha_composite(canvas, highlight)

    return canvas.resize((1024, 1024), Image.LANCZOS)


def build_icns(master, compact):
    os.makedirs(RESOURCES, exist_ok=True)
    master.save(os.path.join(RESOURCES, "AppIcon-1024.png"))

    iconset = os.path.join(RESOURCES, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    # Every size macOS asks for. Omitting any of them makes the icon fall back to a
    # blurry upscale somewhere in the system — usually Get Info or Spotlight.
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = size * scale
            suffix = "" if scale == 1 else "@2x"
            source = compact if pixels <= 32 else master
            source.resize((pixels, pixels), Image.LANCZOS).save(
                os.path.join(iconset, f"icon_{size}x{size}{suffix}.png")
            )

    icns = os.path.join(RESOURCES, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print(f"wrote {icns}")
    return icns


if __name__ == "__main__":
    build_icns(draw_icon(), draw_icon(compact=True))
    sys.exit(0)

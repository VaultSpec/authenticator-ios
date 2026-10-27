#!/usr/bin/env python3
"""Thumbnails for the Scan & Connect video: 1280×720 (YouTube) and 1080×1920 (Shorts / Reels cover).

  python marketing/video/connect/make_connect_thumbnail.py

Frames come from VaultSpec-Scan-and-Connect.mp4: the old phone showing the cloud, the new phone in the
vault it received. The landscape thumbnail is also embedded in the video as its cover.
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from make_thumbnail import backdrop, device, place  # noqa: E402
from make_video import ACCENT, GRAY, WHITE, app_icon, font  # noqa: E402

VIDEO = HERE / "VaultSpec-Scan-and-Connect.mp4"
CLOUD_AT, VAULT_AT = 5.0, 41.0   # seconds into the video


def frame(seconds):
    out = HERE / f".frame_{seconds}.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(seconds), "-i", str(VIDEO), "-frames:v", "1", str(out)], check=True)
    img = Image.open(out).convert("RGB")
    out.unlink()
    return img


def arrow(d, x, y, length):
    """A dotted trail of particles from the old phone to the new one."""
    for i in range(14):
        t = i / 13
        r = 3 + 4 * t
        cx = x + length * t
        d.ellipse((cx - r, y - r, cx + r, y + r), fill=(110, 170, 255, int(90 + 165 * t)))


def landscape(cloud, vault):
    img = backdrop(1280, 720)
    place(img, device(cloud, 540, "iphone"), 610, 120, angle=-6)
    place(img, device(vault, 580, "iphone"), 905, 75, angle=5)
    d = ImageDraw.Draw(img, "RGBA")
    arrow(d, 862, 410, 50)
    icon = app_icon(68)
    img.alpha_composite(icon, (66, 66))
    d.text((150, 70), "VaultSpec", font=font("bold", 38), fill=WHITE)
    d.text((150, 114), "Authenticator", font=font("medium", 22), fill=GRAY)
    d.text((62, 220), "SCAN &", font=font("bold", 104), fill=WHITE)
    d.text((62, 328), "CONNECT", font=font("bold", 104), fill=ACCENT)
    d.text((68, 462), "Move your vault to a new phone", font=font("semibold", 32), fill=WHITE)
    d.text((68, 506), "in seconds", font=font("semibold", 32), fill=GRAY)
    d.text((68, 600), "iPhone  ·  iPad  ·  Android", font=font("medium", 26), fill=GRAY)
    out = HERE / "thumbnail.png"
    img.convert("RGB").save(out)
    return out


def vertical(cloud, vault):
    img = backdrop(1080, 1920)
    d = ImageDraw.Draw(img, "RGBA")
    icon = app_icon(140)
    img.alpha_composite(icon, ((1080 - 140) // 2, 150))
    for y, text, fnt, color in ((330, "VAULTSPEC AUTHENTICATOR", font("semibold", 34), GRAY),
                                (390, "SCAN &", font("bold", 150), WHITE),
                                (540, "CONNECT", font("bold", 150), ACCENT)):
        d.text(((1080 - d.textlength(text, font=fnt)) / 2, y), text, font=fnt, fill=color)
    place(img, device(cloud, 800, "iphone"), 70, 800, angle=-6)
    place(img, device(vault, 860, "iphone"), 545, 770, angle=5)
    d = ImageDraw.Draw(img, "RGBA")
    f = font("semibold", 42)
    label = "Move your vault to a new phone"
    d.text(((1080 - d.textlength(label, font=f)) / 2, 1785), label, font=f, fill=WHITE)
    out = HERE / "thumbnail-vertical.png"
    img.convert("RGB").save(out)
    return out


def embed_cover(cover):
    tmp = VIDEO.with_suffix(".tmp.mp4")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(VIDEO), "-i", str(cover), "-map", "0", "-map", "1",
                    "-c", "copy", "-c:v:1", "png", "-disposition:v:1", "attached_pic", "-movflags", "+faststart", str(tmp)], check=True)
    tmp.replace(VIDEO)


if __name__ == "__main__":
    cloud, vault = frame(CLOUD_AT), frame(VAULT_AT)
    cover = landscape(cloud, vault)
    vertical(cloud, vault)
    embed_cover(cover)
    print("thumbnail.png  thumbnail-vertical.png  (cover embedded in the video)")

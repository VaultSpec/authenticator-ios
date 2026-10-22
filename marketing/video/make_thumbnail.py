#!/usr/bin/env python3
"""Thumbnails for the Apple launch video: 1280×720 (YouTube) and 1080×1920 (Shorts / Reels cover).

  python marketing/video/make_thumbnail.py
"""
import subprocess

from PIL import Image, ImageDraw, ImageFilter

from make_video import ACCENT, BUILD, GRAY, REC, ROOT, WHITE, app_icon, apple_logo, font

AMBER = (255, 184, 77)


def frame(clip, seconds):
    BUILD.mkdir(parents=True, exist_ok=True)
    out = BUILD / f"thumb_{clip}.png"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(seconds), "-i", str(REC / f"{clip}.mp4"), "-frames:v", "1", str(out)], check=True)
    return Image.open(out).convert("RGB")


def backdrop(w, h):
    img = Image.new("RGB", (w, h), (8, 9, 14))
    glow = Image.new("RGB", (w, h), (8, 9, 14))
    d = ImageDraw.Draw(glow)
    d.ellipse((w * 0.35, -h * 0.3, w * 1.3, h * 1.1), fill=(14, 52, 140))
    d.ellipse((-w * 0.3, h * 0.5, w * 0.5, h * 1.4), fill=(40, 20, 90))
    return Image.blend(img, glow.filter(ImageFilter.GaussianBlur(max(w, h) // 6)), 0.85).convert("RGBA")


def device(screen, height, kind):
    """iPhone (Dynamic Island) or iPad body around a screenshot, [height] px tall, transparent background."""
    k = 2
    sh = height * k
    sw = round(sh * screen.width / screen.height)
    radius = round(sw * (0.13 if kind == "iphone" else 0.045))
    bezel, rail = round(sw * (0.03 if kind == "iphone" else 0.025)), round(sw * 0.008)
    body = bezel + rail
    img = Image.new("RGBA", (sw + 2 * body, sh + 2 * body), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius + body, fill=(150, 156, 170))
    d.rounded_rectangle((rail, rail, img.width - 1 - rail, img.height - 1 - rail), radius=radius + bezel, fill=(4, 4, 6))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=radius, fill=255)
    img.paste(screen.resize((sw, sh), Image.LANCZOS), (body, body), mask)
    if kind == "iphone":
        iw, ih = sw * 0.286, sw * 0.084
        d.rounded_rectangle((body + (sw - iw) / 2, body + sw * 0.025, body + (sw + iw) / 2, body + sw * 0.025 + ih), radius=ih / 2, fill="black")
    return img.resize((img.width // k, img.height // k), Image.LANCZOS)


def place(img, dev, x, y, angle=0):
    dev = dev.rotate(angle, resample=Image.BICUBIC, expand=True)
    shadow = Image.new("RGBA", dev.size, (0, 0, 0, 0))
    shadow.putalpha(dev.getchannel("A").point(lambda a: a * 0.6))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    img.alpha_composite(shadow, (x + 10, y + 24))
    img.alpha_composite(dev, (x, y))


def badge(d, img, x, y, scale=1.0):
    small, big = font("medium", int(20 * scale)), font("semibold", int(38 * scale))
    tw = max(d.textlength("Download on the", font=small), d.textlength("App Store", font=big))
    w, h = int(tw + 132 * scale), int(94 * scale)
    d.rounded_rectangle((x, y, x + w, y + h), radius=int(22 * scale), fill=(0, 0, 0), outline=(150, 150, 158), width=2)
    mark = apple_logo(int(48 * scale))
    img.alpha_composite(mark, (x + int(30 * scale), y + int(21 * scale)))
    d.text((x + int(96 * scale), y + int(15 * scale)), "Download on the", font=small, fill=WHITE)
    d.text((x + int(94 * scale), y + int(37 * scale)), "App Store", font=big, fill=WHITE)


def landscape(phone, pad):
    img = backdrop(1280, 720)
    place(img, device(pad, 560, "ipad"), 730, 90, angle=-6)
    place(img, device(phone, 600, "iphone"), 1000, 80, angle=5)
    d = ImageDraw.Draw(img)
    icon = app_icon(68)
    img.alpha_composite(icon, (66, 66))
    d.text((150, 70), "VaultSpec", font=font("bold", 38), fill=WHITE)
    d.text((150, 114), "Authenticator", font=font("medium", 22), fill=GRAY)
    d.text((62, 210), "NOW ON", font=font("bold", 104), fill=WHITE)
    d.text((62, 318), "APP STORE", font=font("bold", 104), fill=AMBER)
    d.text((68, 452), "iPhone  ·  iPad  ·  Mac", font=font("semibold", 32), fill=GRAY)
    badge(d, img, 66, 524)
    img.convert("RGB").save(ROOT / "thumbnail.png")


def vertical(phone, pad):
    img = backdrop(1080, 1920)
    d = ImageDraw.Draw(img)
    icon = app_icon(140)
    img.alpha_composite(icon, ((1080 - 140) // 2, 110))
    for y, text, fnt, color in ((290, "VAULTSPEC AUTHENTICATOR", font("semibold", 34), GRAY),
                                (350, "NOW ON", font("bold", 150), WHITE),
                                (500, "APP STORE", font("bold", 150), AMBER)):
        d.text(((1080 - d.textlength(text, font=fnt)) / 2, y), text, font=fnt, fill=color)
    place(img, device(pad, 900, "ipad"), 30, 760, angle=-5)
    place(img, device(phone, 1000, "iphone"), 560, 720, angle=5)
    d = ImageDraw.Draw(img)
    f = font("semibold", 40)
    label = "iPhone  ·  iPad  ·  Mac"
    d.text(((1080 - d.textlength(label, font=f)) / 2, 1760), label, font=f, fill=WHITE)
    img.convert("RGB").save(ROOT / "thumbnail-vertical.png")


if __name__ == "__main__":
    phone = frame("iphone-codes", 0.5)
    pad = frame("ipad-codes", 1.0)
    landscape(phone, pad)
    vertical(phone, pad)
    print("thumbnail.png  thumbnail-vertical.png")

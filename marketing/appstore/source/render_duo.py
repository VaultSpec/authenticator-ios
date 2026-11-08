"""App Store screenshots for iPhone Duo (outer display, 1398 × 2034): the same dark studio and 3D devices
as render_store.py, with the Duo's wider body and a punch-hole camera instead of the Dynamic Island.

  python render_duo.py ../iphone-duo/raw ../iphone-duo

The inner display set reads ../iphone-duo/raw-inner (simctl ... screenshot --display 3, unfolded).

The captures are the outer display of the Duo simulator (`simctl io <id> screenshot --display 1`),
running the demo vault: launch with -demoVault and -screen settings|add|connect, or -demoLocked.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw


import render_store as rs  # noqa: E402  (its own scenes only run as a script)

DW, DH = 1398, 2034
GREEN, AMBER, VIOLET = rs.GREEN, rs.AMBER, rs.VIOLET


def duo_face(shot, kind):
    """The Duo's front: a titanium rim, slim even bezels, rounder corners and a small punch-hole camera."""
    sw, sh = shot.size
    ring, bezel, screen_r = int(sw * 0.012), int(sw * 0.022), int(sw * 0.105)
    W, H = sw + 2 * (ring + bezel), sh + 2 * (ring + bezel)
    R = screen_r + ring + bezel
    face = Image.new("RGBA", (W, H))
    gx = np.linspace(0, 1, W)[None, :]
    gy = np.linspace(0, 1, H)[:, None]
    t = gx * 0.6 + gy * 0.4
    metal = np.array([96, 102, 116]) + np.cos(t[..., None] * 9) * np.array([46, 46, 50])
    face.paste(Image.fromarray(np.clip(metal, 0, 255).astype(np.uint8)), (0, 0), rs.rounded_mask((W, H), R))
    d = ImageDraw.Draw(face)
    d.rounded_rectangle([ring, ring, W - ring - 1, H - ring - 1], R - ring, fill=(4, 5, 8, 255))
    d.rounded_rectangle([1, 1, W - 2, H - 2], R - 1, outline=(220, 228, 245, 150), width=max(2, ring // 5))
    face.paste(shot.convert("RGB"), (ring + bezel, ring + bezel), rs.rounded_mask((sw, sh), screen_r))
    cam = sw * 0.032
    cx, cy = W / 2, ring + bezel + sw * 0.034
    d.ellipse([cx - cam / 2, cy - cam / 2, cx + cam / 2, cy + cam / 2], fill=(0, 0, 0, 255))
    glare = np.clip(1 - (np.linspace(0, 1, sw)[None, :] * 0.9 + np.linspace(0, 1, sh)[:, None] * 0.55) * 1.4, 0, 1) * 30
    glare_img = Image.new("RGBA", (sw, sh), (255, 255, 255, 0))
    glare_img.putalpha(Image.fromarray(glare.astype(np.uint8)))
    screen = Image.new("RGBA", (W, H))
    screen.paste(glare_img, (ring + bezel, ring + bezel), rs.rounded_mask((sw, sh), screen_r))
    return Image.alpha_composite(face, screen), R


rs.device_face = duo_face
rs.RAW, rs.OUT = sys.argv[1], sys.argv[2]


def canvas(glow=(0.5, 0.66)):
    return rs.backdrop(DW * rs.SS, DH * rs.SS, glow)


def text(c, eyebrow, title, subtitle):
    rs.text_block(c, eyebrow, title, subtitle, 104, scale=0.92)


c = canvas()
text(c, "Built for iPhone Duo", "Your 2FA codes,\nopen or folded.", "Every code a glance away on the outer display.")
rs.badges(c, [("AES-256-GCM", GREEN), ("Face ID", rs.BLUE), ("Works offline", VIOLET)], 560, scale=0.92)
rs.place(c, rs.shot("duo-codes"), "phone", 699, 1300, 1080, yaw=-20, pitch=7, roll=-3)
rs.finish(c, "duo-01-codes", (DW, DH))

c = canvas()
text(c, "Scan & Connect", "A new device\nin seconds.", "Scan the cloud on your other device,\nenter your vault password. Done.")
rs.badges(c, [("End-to-end encrypted", GREEN), ("iPhone · iPad · Android", rs.BLUE)], 600, scale=0.92)
rs.place(c, rs.shot("duo-connect"), "phone", 699, 1300, 1080, yaw=18, pitch=7, roll=3)
rs.finish(c, "duo-02-connect", (DW, DH))

c = canvas()
text(c, "Security controls", "Locked down\nby default.", "Auto-lock, screenshot blocking\nand tap to reveal.")
rs.badges(c, [("Blocks screenshots", GREEN), ("Auto-lock", AMBER)], 600, scale=0.92)
rs.place(c, rs.shot("duo-settings"), "phone", 699, 1300, 1080, yaw=-16, pitch=7, roll=-2)
rs.finish(c, "duo-03-security", (DW, DH))

c = canvas()
text(c, "Setup in seconds", "Add any service,\nyour way.", "Scan a QR code or paste a setup link.\nGroup accounts in your own categories.")
rs.badges(c, [("QR or setup link", rs.BLUE), ("Custom categories", VIOLET)], 600, scale=0.92)
rs.place(c, rs.shot("duo-add"), "phone", 699, 1300, 1080, yaw=16, pitch=6, roll=2)
rs.finish(c, "duo-04-add", (DW, DH))

c = canvas((0.5, 0.72))
text(c, "Zero knowledge", "One password.\nZero exposure.", "Your vault is sealed with AES-256\nand only opens on your device.")
rs.badges(c, [("Keychain protected", GREEN), ("No tracking", AMBER)], 600, scale=0.92)
rs.place(c, rs.shot("duo-lock"), "phone", 699, 1300, 1080, yaw=-12, pitch=12, roll=-2)
rs.finish(c, "duo-05-lock", (DW, DH))

# ─── Inner display, unfolded (2853 × 2007, landscape) ────────────────────────

IW, IH = 2853, 2007
INNER = sys.argv[1].rstrip("/") + "-inner"   # raw-inner/: captures of the inner display (--display 3)


def inner_face(shot, kind):
    """The unfolded Duo: thin even bezels, soft corners and a faint hinge line down the middle."""
    sw, sh = shot.size
    ring, bezel, screen_r = int(sh * 0.012), int(sh * 0.02), int(sh * 0.07)
    W, H = sw + 2 * (ring + bezel), sh + 2 * (ring + bezel)
    R = screen_r + ring + bezel
    face = Image.new("RGBA", (W, H))
    gx = np.linspace(0, 1, W)[None, :]
    gy = np.linspace(0, 1, H)[:, None]
    metal = np.array([96, 102, 116]) + np.cos((gx * 0.6 + gy * 0.4)[..., None] * 9) * np.array([46, 46, 50])
    face.paste(Image.fromarray(np.clip(metal, 0, 255).astype(np.uint8)), (0, 0), rs.rounded_mask((W, H), R))
    d = ImageDraw.Draw(face)
    d.rounded_rectangle([ring, ring, W - ring - 1, H - ring - 1], R - ring, fill=(4, 5, 8, 255))
    d.rounded_rectangle([1, 1, W - 2, H - 2], R - 1, outline=(220, 228, 245, 150), width=max(2, ring // 5))
    face.paste(shot.convert("RGB"), (ring + bezel, ring + bezel), rs.rounded_mask((sw, sh), screen_r))
    hinge = Image.new("RGBA", (W, H))
    # The fold runs across the short side: vertical in landscape, horizontal in portrait
    for k, a in ((-2, 10), (-1, 18), (0, 26), (1, 18), (2, 10)):
        line = [(W // 2 + k, ring), (W // 2 + k, H - ring)] if W > H else [(ring, H // 2 + k), (W - ring, H // 2 + k)]
        ImageDraw.Draw(hinge).line(line, fill=(255, 255, 255, a))
    return Image.alpha_composite(face, hinge), R


def inner_canvas(glow=(0.66, 0.6)):
    return rs.backdrop(IW * rs.SS, IH * rs.SS, glow)


def inner_scene(name, eyebrow, title, subtitle, chips, yaw):
    rs.device_face = inner_face
    rs.RAW = INNER
    c = inner_canvas()
    rs.text_block(c, eyebrow, title, subtitle, 640, scale=1.05, align="left", left=0.06)
    d = ImageDraw.Draw(c)
    x, y = 0.06 * IW * rs.SS, 1170 * rs.SS
    fnt = rs.font("medium", 32)
    for label, color in chips:
        w = d.textlength(label, font=fnt) + 96 * rs.SS
        h = 68 * rs.SS
        d.rounded_rectangle([x, y, x + w, y + h], h / 2, fill=(14, 22, 48, 235), outline=(70, 105, 200, 150), width=2 * rs.SS)
        r = 8 * rs.SS
        d.ellipse([x + 28 * rs.SS, y + h / 2 - r, x + 28 * rs.SS + 2 * r, y + h / 2 + r], fill=color + (255,))
        d.text((x + 56 * rs.SS, y + h / 2), label, font=fnt, fill=rs.WHITE, anchor="lm")
        x += w + 18 * rs.SS
    rs.place(c, rs.shot(name), "phone", 1990, 1010, 1260, yaw=yaw, pitch=6, roll=-2, depth=0.03)
    rs.finish(c, name.replace("inner-", "duo-inner-"), (IW, IH))
    rs.device_face = duo_face


inner_scene("inner-codes", "Built for iPhone Duo", "Unfold for\nmore codes.", "Two columns of codes on the\nbig inner display.",
            [("AES-256-GCM", GREEN), ("Face ID", rs.BLUE)], -16)
inner_scene("inner-connect", "Scan & Connect", "A new device\nin seconds.", "Scan the cloud on your other device,\nenter your vault password. Done.",
            [("End-to-end encrypted", GREEN)], -14)
inner_scene("inner-settings", "Security controls", "Locked down\nby default.", "Auto-lock, screenshot blocking\nand tap to reveal.",
            [("Blocks screenshots", GREEN), ("Auto-lock", AMBER)], -16)
inner_scene("inner-add", "Setup in seconds", "Add any\nservice.", "Scan a QR code or paste a setup link.\nGroup accounts in your own categories.",
            [("Custom categories", VIOLET)], -14)
inner_scene("inner-lock", "Zero knowledge", "Sealed on\nyour device.", "AES-256 encryption. One password\nonly you know.",
            [("No tracking", AMBER)], -16)

# ─── Inner display, unfolded, portrait (2007 × 2853) ─────────────────────────

rs.device_face = inner_face
rs.RAW = INNER
c = rs.backdrop(2007 * rs.SS, 2853 * rs.SS, (0.5, 0.64))
rs.text_block(c, "Built for iPhone Duo", "Open it up.\nYour codes, bigger.", "Every code at a glance on the inner display.", 150, scale=1.2)
rs.badges(c, [("AES-256-GCM", GREEN), ("Face ID", rs.BLUE), ("Works offline", VIOLET)], 760, scale=1.2)
rs.place(c, rs.shot("inner-portrait"), "phone", 1003, 1830, 1640, yaw=-18, pitch=7, roll=-3, depth=0.03)
rs.finish(c, "duo-inner-portrait", (2007, 2853))
rs.device_face = duo_face

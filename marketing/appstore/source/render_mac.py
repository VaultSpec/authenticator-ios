"""Mac App Store screenshots (2880 × 1800): the real Mac window in perspective, beside the headline."""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_MAC, RAW_IOS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]

# Reuse the backdrop, devices, type and badges from the iPhone/iPad renderer (everything above its layouts)
source = open(os.path.join(HERE, "render_store.py")).read()
shared = source[: source.index("# ─── iPhone")]
sys.argv = [sys.argv[0], RAW_IOS, OUT]
exec(compile(shared, "render_store.py", "exec"))

MW, MH = 2880, 1800


def place_window(canvas, window, cx, cy, width, yaw=-12, pitch=4, roll=0):
    """A flat window (with its transparent rounded corners) in perspective, lit from behind, with a soft shadow."""
    w, h = window.size
    s = width * SS / w
    f = 3.2 * width * SS
    ya, pa, ra = map(math.radians, (yaw, pitch, roll))

    def project(u, v):
        x, y, z = (u - w / 2) * s, (v - h / 2) * s, 0.0
        x, y = x * math.cos(ra) - y * math.sin(ra), x * math.sin(ra) + y * math.cos(ra)
        x, z = x * math.cos(ya) + z * math.sin(ya), -x * math.sin(ya) + z * math.cos(ya)
        y, z = y * math.cos(pa) - z * math.sin(pa), y * math.sin(pa) + z * math.cos(pa)
        k = f / (f + z)
        return cx * SS + x * k, cy * SS + y * k

    corners = [project(0, 0), project(w, 0), project(w, h), project(0, h)]
    coeffs = find_coeffs(corners, [(0, 0), (w, 0), (w, h), (0, h)])
    warped = window.convert("RGBA").transform(canvas.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    alpha = warped.split()[3]

    glow = Image.new("RGBA", canvas.size, (30, 110, 255, 0))
    glow.putalpha(alpha.filter(ImageFilter.GaussianBlur(110 * SS)).point(lambda a: int(a * 0.6)))
    canvas.alpha_composite(glow)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    moved = Image.new("L", canvas.size, 0)
    moved.paste(alpha, (int(30 * SS), int(60 * SS)))
    shadow.putalpha(moved.filter(ImageFilter.GaussianBlur(50 * SS)).point(lambda a: int(a * 0.8)))
    canvas.alpha_composite(shadow)
    # A hairline that catches the light around the window edge
    edge = Image.new("RGBA", canvas.size, (200, 215, 255, 0))
    ring = alpha.filter(ImageFilter.MaxFilter(5)).point(lambda a: 255 if a > 128 else 0)
    inner = alpha.point(lambda a: 255 if a > 128 else 0)
    edge.putalpha(Image.fromarray((np.array(ring, dtype=np.int16) - np.array(inner, dtype=np.int16)).clip(0, 255).astype(np.uint8)).point(lambda a: int(a * 0.5)))
    canvas.alpha_composite(edge)
    canvas.alpha_composite(warped)


def left_badges(canvas, items, x, y, scale=1.0):
    d = ImageDraw.Draw(canvas)
    fnt = font("medium", 30 * scale)
    h, gap, pad = 64 * SS * scale, 16 * SS * scale, 26 * SS * scale
    X, Y = x * SS, y * SS
    for t, color in items:
        w = d.textlength(t, font=fnt) + pad * 2 + 30 * SS * scale
        if X + w > canvas.size[0] * 0.42:
            X, Y = x * SS, Y + h + gap
        d.rounded_rectangle([X, Y, X + w, Y + h], h / 2, fill=(14, 22, 48, 235), outline=(70, 105, 200, 150), width=2 * SS)
        r = 8 * SS * scale
        cxd, cyd = X + pad + r, Y + h / 2
        d.ellipse([cxd - r, cyd - r, cxd + r, cyd + r], fill=color + (255,))
        d.text((cxd + r + 14 * SS * scale, cyd), t, font=fnt, fill=WHITE, anchor="lm")
        X += w + gap


def mac(name, eyebrow, title, subtitle, badges, window, glow=(0.66, 0.5), extra=None):
    c = backdrop(MW * SS, MH * SS, glow)
    text_block(c, eyebrow, title, subtitle, 600, scale=0.98, align="left", left=0.055)
    left_badges(c, badges, 160, 1150, scale=1.0)
    if extra:
        extra(c)
    else:
        place_window(c, Image.open(f"{RAW_MAC}/{window}.png"), 2090, 900, 1440, yaw=-13, pitch=4, roll=0)
    finish(c, name, (MW, MH))


GREEN, AMBER, VIOLET = (52, 211, 153), (255, 176, 32), (167, 139, 250)

mac("mac-01-codes", "VaultSpec for Mac", "Your 2FA codes,\nnext to your work.",
    "A native Mac app with Touch ID,\nkeyboard shortcuts and a live grid.",
    [("Touch ID", BLUE), ("AES-256-GCM", GREEN), ("Works offline", VIOLET)], "mac-codes")

mac("mac-02-security", "Security controls", "Locked down\nby default.",
    "Auto-Lock when you step away,\ntap to reveal and password reminders.",
    [("Auto-Lock", AMBER), ("Touch ID", BLUE)], "mac-settings")

mac("mac-03-add", "Setup in seconds", "Add any service\nin seconds.",
    "Paste a setup link or key.\nSHA-1, SHA-256 and SHA-512.",
    [("Setup link or key", BLUE), ("6 or 8 digits", VIOLET)], "mac-add")


def devices(c):
    place_window(c, Image.open(f"{RAW_MAC}/mac-codes.png"), 2020, 820, 1300, yaw=-10, pitch=4)
    place(c, shot("ipad-codes"), "ipad", 2560, 1250, 900, yaw=-18, pitch=6, roll=-2, depth=0.035, glow=False)
    place(c, shot("iphone-codes"), "phone", 1500, 1300, 820, yaw=16, pitch=7, roll=3, glow=False)


mac("mac-04-devices", "Mac · iPhone · iPad", "One vault on\nevery device.",
    "Encrypted cloud backup restores your codes\non any Mac, iPhone or iPad.",
    [("End-to-end encrypted backup", GREEN)], None, extra=devices)

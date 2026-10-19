"""App Store screenshots for VaultSpec Authenticator: real captures on 3D-extruded devices in a dark studio."""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = sys.argv[1]   # folder with the simulator captures
OUT = sys.argv[2]   # output folder
SS = 2              # supersampling for clean edges
FONTS = "/Volumes/Projects/Orgs/vaultspec/vaultspec-pass/FE/android/app/src/main/res/font"

BLUE = (10, 132, 255)
SKY = (90, 170, 255)
WHITE = (255, 255, 255)
MUTED = (158, 170, 204)


def font(weight, size):
    return ImageFont.truetype(f"{FONTS}/inter_{weight}.ttf", int(size * SS))


# ─── Backdrop ────────────────────────────────────────────────────────────────

def backdrop(w, h, glow=(0.5, 0.62)):
    """Navy studio: spotlight from above, a blue bloom behind the product, violet in a corner, a faint floor grid."""
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    img = np.zeros((h, w, 3))
    img += (np.array([7, 11, 30]) * (1 - y[..., None]) + np.array([2, 4, 12]) * y[..., None])
    gx, gy = glow
    bloom = np.exp(-(((x - gx) / 0.42) ** 2 + ((y - gy) / 0.30) ** 2) * 1.4)
    img += bloom[..., None] * np.array([10, 70, 230]) * 0.55
    violet = np.exp(-(((x - 0.05) / 0.5) ** 2 + ((y - 0.95) / 0.35) ** 2) * 1.5)
    img += violet[..., None] * np.array([80, 30, 190]) * 0.35
    cone = np.exp(-(((x - 0.5) / 0.35) ** 2) * 1.2) * np.clip(1 - y * 1.6, 0, 1)
    img += cone[..., None] * np.array([60, 80, 140]) * 0.22
    base = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")

    # Floor grid in perspective, fading towards the horizon and the sides
    grid = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(grid)
    horizon, vx = int(h * 0.80), w / 2
    for i in range(-14, 15):
        d.line([(vx + i * w * 0.02, horizon), (vx + i * w * 0.32, h)], fill=(120, 160, 255, 34), width=max(1, SS))
    for k in range(1, 12):
        yy = horizon + (h - horizon) * (k / 11) ** 2.2
        d.line([(0, yy), (w, yy)], fill=(120, 160, 255, 30), width=max(1, SS))
    fade = np.zeros((h, w))
    fade[horizon:, :] = np.linspace(0, 1, h - horizon)[:, None] ** 0.8
    fade *= np.exp(-(((x - 0.5) / 0.45) ** 2))
    alpha = (np.array(grid.split()[3]) * fade).astype(np.uint8)
    grid.putalpha(Image.fromarray(alpha))
    return Image.alpha_composite(base, grid)


# ─── Devices ─────────────────────────────────────────────────────────────────

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def device_face(shot, kind):
    """The flat front of the device: titanium rim, black bezel, the capture, Dynamic Island and a soft glare."""
    sw, sh = shot.size
    if kind == "phone":
        ring, bezel, screen_r = int(sw * 0.014), int(sw * 0.026), int(sw * 0.125)
    else:
        ring, bezel, screen_r = int(sw * 0.008), int(sw * 0.03), int(sw * 0.035)
    W, H = sw + 2 * (ring + bezel), sh + 2 * (ring + bezel)
    R = screen_r + ring + bezel
    face = Image.new("RGBA", (W, H))

    gx = np.linspace(0, 1, W)[None, :]
    gy = np.linspace(0, 1, H)[:, None]
    t = (gx * 0.6 + gy * 0.4)
    metal = (np.array([96, 102, 116]) + np.cos(t[..., None] * 9) * np.array([46, 46, 50]))
    face.paste(Image.fromarray(np.clip(metal, 0, 255).astype(np.uint8)), (0, 0), rounded_mask((W, H), R))
    d = ImageDraw.Draw(face)
    d.rounded_rectangle([ring, ring, W - ring - 1, H - ring - 1], R - ring, fill=(4, 5, 8, 255))
    d.rounded_rectangle([1, 1, W - 2, H - 2], R - 1, outline=(220, 228, 245, 150), width=max(2, ring // 5))

    face.paste(shot.convert("RGB"), (ring + bezel, ring + bezel), rounded_mask((sw, sh), screen_r))
    if kind == "phone":
        iw, ih, top = sw * 0.286, sw * 0.084, sw * 0.025
        cx = W / 2
        d.rounded_rectangle([cx - iw / 2, ring + bezel + top, cx + iw / 2, ring + bezel + top + ih], ih / 2, fill=(0, 0, 0, 255))

    glare = np.zeros((sh, sw))
    gxs = np.linspace(0, 1, sw)[None, :]
    gys = np.linspace(0, 1, sh)[:, None]
    glare += np.clip(1 - (gxs * 0.9 + gys * 0.55) * 1.4, 0, 1) * 34
    glare_img = Image.new("RGBA", (sw, sh), (255, 255, 255, 0))
    glare_img.putalpha(Image.fromarray(glare.astype(np.uint8)))
    screen = Image.new("RGBA", (W, H))
    screen.paste(glare_img, (ring + bezel, ring + bezel), rounded_mask((sw, sh), screen_r))
    return Image.alpha_composite(face, screen), R


def outline(W, H, R, n=64):
    """Points around a rounded rectangle (clockwise from the top-left corner) with outward normals."""
    pts, normals = [], []
    corners = [(R, R, 180), (W - R, R, 270), (W - R, H - R, 0), (R, H - R, 90)]
    for cx, cy, start in corners:
        for k in range(n + 1):
            a = math.radians(start + 90 * k / n)
            pts.append((cx + R * math.cos(a), cy + R * math.sin(a)))
            normals.append((math.cos(a), math.sin(a)))
    return pts, normals


def find_coeffs(dst, src):
    """PIL perspective coefficients mapping output points (dst) back to input points (src)."""
    m = []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(m, dtype=float)
    b = np.array(src, dtype=float).reshape(8)
    return np.linalg.solve(a, b).tolist()


def place(canvas, shot, kind, cx, cy, height, yaw=-18, pitch=6, roll=0, depth=0.075, glow=True):
    """Draws the device in 3D: rotated, in perspective, with an extruded metal side and a soft shadow."""
    face, R = device_face(shot, kind)
    W, H = face.size
    s = height * SS / H
    f = 3.0 * height * SS
    D = depth * H
    ya, pa, ra = map(math.radians, (yaw, pitch, roll))

    def project(u, v, z):
        x, y = (u - W / 2) * s, (v - H / 2) * s
        z *= s
        x, y = x * math.cos(ra) - y * math.sin(ra), x * math.sin(ra) + y * math.cos(ra)
        x, z = x * math.cos(ya) + z * math.sin(ya), -x * math.sin(ya) + z * math.cos(ya)
        y, z = y * math.cos(pa) - z * math.sin(pa), y * math.sin(pa) + z * math.cos(pa)
        k = f / (f + z)
        return cx * SS + x * k, cy * SS + y * k, z

    def rotate_normal(nx, ny):
        x, y, z = nx, ny, 0.0
        x, y = x * math.cos(ra) - y * math.sin(ra), x * math.sin(ra) + y * math.cos(ra)
        x, z = x * math.cos(ya) + z * math.sin(ya), -x * math.sin(ya) + z * math.cos(ya)
        y, z = y * math.cos(pa) - z * math.sin(pa), y * math.sin(pa) + z * math.cos(pa)
        return x, y, z

    pts, normals = outline(W, H, R)
    front = [project(u, v, 0) for u, v in pts]
    back = [project(u, v, D) for u, v in pts]

    # Glow and shadow under the device
    sil = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(sil).polygon([(x, y) for x, y, _ in back] + [(x, y) for x, y, _ in front][::-1], fill=255)
    ImageDraw.Draw(sil).polygon([(x, y) for x, y, _ in front], fill=255)
    if glow:
        g = sil.filter(ImageFilter.GaussianBlur(90 * SS))
        layer = Image.new("RGBA", canvas.size, (30, 110, 255, 0))
        layer.putalpha(g.point(lambda a: int(a * 0.55)))
        canvas.alpha_composite(layer)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh_mask = Image.new("L", canvas.size, 0)
    sh_mask.paste(sil, (int(24 * SS), int(46 * SS)))
    shadow.putalpha(sh_mask.filter(ImageFilter.GaussianBlur(38 * SS)).point(lambda a: int(a * 0.75)))
    canvas.alpha_composite(shadow)

    # Extruded side: back plate, then the edge strips that face the camera, lit from the top left
    body = Image.new("RGBA", canvas.size)
    bd = ImageDraw.Draw(body)
    bd.polygon([(x, y) for x, y, _ in back], fill=(38, 42, 52, 255))
    light = np.array([-0.45, -0.75, -0.5])
    light /= np.linalg.norm(light)
    quads = []
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        n = rotate_normal(*normals[i])
        if n[2] > 0.02:
            continue
        diffuse = max(0.0, -float(np.dot(n, light)))
        spec = diffuse ** 12
        shade = 0.42 + 0.58 * diffuse
        color = tuple(int(min(255, c * shade + 255 * spec * 0.6)) for c in (150, 158, 176)) + (255,)
        quad = [front[i][:2], front[j][:2], back[j][:2], back[i][:2]]
        quads.append(((front[i][2] + back[i][2]) / 2, quad, color))
    for _, quad, color in sorted(quads, key=lambda q: -q[0]):
        bd.polygon(quad, fill=color)
    canvas.alpha_composite(body)

    corners = [project(0, 0, 0), project(W, 0, 0), project(W, H, 0), project(0, H, 0)]
    coeffs = find_coeffs([c[:2] for c in corners], [(0, 0), (W, 0), (W, H), (0, H)])
    canvas.alpha_composite(face.transform(canvas.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC))


# ─── Type and callouts ───────────────────────────────────────────────────────

def text_block(canvas, eyebrow, title, subtitle, top, scale=1.0, align="center", left=0.08):
    d = ImageDraw.Draw(canvas)
    w = canvas.size[0]
    y = top * SS

    def line(txt, fnt, fill, spacing=0):
        nonlocal y
        if spacing:
            widths = [d.textlength(ch, font=fnt) + spacing * SS for ch in txt]
            total = sum(widths) - spacing * SS
            x = (w - total) / 2 if align == "center" else left * w
            for ch, cw in zip(txt, widths):
                d.text((x, y), ch, font=fnt, fill=fill)
                x += cw
            y += fnt.size * 1.9
            return
        tw = d.textlength(txt, font=fnt)
        x = (w - tw) / 2 if align == "center" else left * w
        d.text((x, y), txt, font=fnt, fill=fill)
        y += fnt.size * 1.12

    line(eyebrow.upper(), font("semibold", 30 * scale), SKY, spacing=5 * scale)
    for t in title.split("\n"):
        line(t, font("bold", 104 * scale), WHITE)
    y += 22 * SS * scale
    for t in subtitle.split("\n"):
        line(t, font("regular", 40 * scale), MUTED)
        y += 6 * SS * scale


def chip(canvas, x, y, label, dot=BLUE, scale=1.0):
    """A floating dark pill with a lit edge and a status dot."""
    d = ImageDraw.Draw(canvas)
    fnt = font("semibold", 32 * scale)
    tw = d.textlength(label, font=fnt)
    h = 78 * SS * scale
    w = tw + 112 * SS * scale
    X, Y = x * SS, y * SS
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([X + 10 * SS, Y + 18 * SS, X + w + 10 * SS, Y + h + 18 * SS], h / 2, fill=(0, 0, 0, 150))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18 * SS)))
    d.rounded_rectangle([X, Y, X + w, Y + h], h / 2, fill=(14, 22, 48, 240), outline=(80, 120, 220, 170), width=2 * SS)
    r = 11 * SS * scale
    cxd, cyd = X + 40 * SS * scale, Y + h / 2
    d.ellipse([cxd - r * 2.2, cyd - r * 2.2, cxd + r * 2.2, cyd + r * 2.2], fill=dot + (60,))
    d.ellipse([cxd - r, cyd - r, cxd + r, cyd + r], fill=dot + (255,))
    d.text((X + 72 * SS * scale, Y + h / 2), label, font=fnt, fill=WHITE, anchor="lm")


def badges(canvas, items, y, scale=1.0):
    """A centred row of small pills under the headline: a coloured dot and a short claim each."""
    d = ImageDraw.Draw(canvas)
    fnt = font("medium", 30 * scale)
    h, gap, pad = 64 * SS * scale, 18 * SS * scale, 26 * SS * scale
    widths = [d.textlength(t, font=fnt) + pad * 2 + 30 * SS * scale for t, _ in items]
    x = (canvas.size[0] - sum(widths) - gap * (len(items) - 1)) / 2
    Y = y * SS
    for (t, color), w in zip(items, widths):
        d.rounded_rectangle([x, Y, x + w, Y + h], h / 2, fill=(14, 22, 48, 235), outline=(70, 105, 200, 150), width=2 * SS)
        r = 8 * SS * scale
        cx, cy = x + pad + r, Y + h / 2
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
        d.text((cx + r + 14 * SS * scale, cy), t, font=fnt, fill=WHITE, anchor="lm")
        x += w + gap


def finish(canvas, name, size):
    img = canvas.convert("RGB").resize(size, Image.LANCZOS)
    img.save(f"{OUT}/{name}.png", optimize=True)
    print("wrote", name, img.size)


def shot(name):
    return Image.open(f"{RAW}/{name}.png")


# ─── iPhone 6.9" (1320 × 2868) ───────────────────────────────────────────────

PW, PH = 1320, 2868
GREEN, AMBER, VIOLET = (52, 211, 153), (255, 176, 32), (167, 139, 250)


def phone_canvas(glow=(0.5, 0.64)):
    return backdrop(PW * SS, PH * SS, glow)


c = phone_canvas()
text_block(c, "VaultSpec Authenticator", "Two-factor codes,\nbuilt for work.", "Encrypted on this device. Synced only if you choose.", 150)
badges(c, [("AES-256-GCM", GREEN), ("Face ID", BLUE), ("Works offline", VIOLET)], 690)
place(c, shot("iphone-codes"), "phone", 660, 1810, 1880, yaw=-20, pitch=7, roll=-3)
finish(c, "iphone-01-codes", (PW, PH))

c = phone_canvas((0.5, 0.66))
text_block(c, "Security controls", "Locked down\nby default.", "Screenshot blocking, tap to reveal\nand password reminders.", 150)
badges(c, [("Blocks screenshots", GREEN), ("Auto-lock", AMBER)], 740)
place(c, shot("iphone-settings"), "phone", 660, 1850, 1840, yaw=18, pitch=7, roll=3)
finish(c, "iphone-02-security", (PW, PH))

c = phone_canvas()
text_block(c, "Setup in seconds", "Add any service\nin seconds.", "Scan a QR code or paste a setup link.\nSHA-1, SHA-256 and SHA-512.", 150)
badges(c, [("QR or setup link", BLUE), ("6 or 8 digits", VIOLET)], 740)
place(c, shot("iphone-add"), "phone", 660, 1850, 1840, yaw=-16, pitch=6, roll=-2)
finish(c, "iphone-03-add", (PW, PH))

c = phone_canvas((0.5, 0.72))
text_block(c, "Zero knowledge", "One password.\nZero exposure.", "Your vault is sealed with AES-256\nand only opens on your device.", 150)
badges(c, [("Keychain protected", GREEN), ("No tracking", AMBER)], 740)
place(c, shot("iphone-lock"), "phone", 660, 2440, 2300, yaw=-12, pitch=16, roll=-2)
finish(c, "iphone-04-lock", (PW, PH))

c = phone_canvas((0.55, 0.62))
text_block(c, "iPhone · iPad · Mac", "One vault on\nevery device.", "Encrypted cloud backup restores on iPhone,\niPad, Mac and Android.", 150)
badges(c, [("End-to-end encrypted backup", GREEN)], 740)
place(c, shot("ipad-codes"), "ipad", 560, 1640, 1420, yaw=22, pitch=6, roll=2, depth=0.035)
place(c, shot("iphone-codes"), "phone", 930, 1980, 1380, yaw=-20, pitch=7, roll=-3, glow=False)
finish(c, "iphone-05-devices", (PW, PH))

# ─── iPad 13" (2064 × 2752) ──────────────────────────────────────────────────

IW, IH = 2064, 2752


def ipad_canvas(glow=(0.5, 0.64)):
    return backdrop(IW * SS, IH * SS, glow)


c = ipad_canvas()
text_block(c, "VaultSpec Authenticator", "Every 2FA code.\nOne secure grid.", "Encrypted on this device. Synced only if you choose.", 140, scale=1.2)
badges(c, [("AES-256-GCM", GREEN), ("Face ID and Touch ID", BLUE), ("Works offline", VIOLET)], 720, scale=1.2)
place(c, shot("ipad-codes"), "ipad", 1032, 1780, 1740, yaw=-16, pitch=7, roll=-2, depth=0.035)
finish(c, "ipad-01-codes", (IW, IH))

c = ipad_canvas()
text_block(c, "Security controls", "Locked down\nby default.", "Screenshot blocking, tap to reveal and password reminders.", 140, scale=1.2)
badges(c, [("Blocks screenshots", GREEN), ("Auto-lock", AMBER)], 720, scale=1.2)
place(c, shot("ipad-settings"), "ipad", 1032, 1780, 1740, yaw=16, pitch=7, roll=2, depth=0.035)
finish(c, "ipad-02-security", (IW, IH))

c = ipad_canvas((0.55, 0.64))
text_block(c, "iPhone · iPad · Mac", "One vault on\nevery device.", "Encrypted cloud backup restores on iPhone, iPad, Mac and Android.", 140, scale=1.2)
badges(c, [("End-to-end encrypted backup", GREEN)], 720, scale=1.2)
place(c, shot("ipad-codes"), "ipad", 900, 1740, 1620, yaw=20, pitch=6, roll=2, depth=0.035)
place(c, shot("iphone-codes"), "phone", 1560, 1990, 1250, yaw=-20, pitch=7, roll=-3, glow=False)
finish(c, "ipad-03-devices", (IW, IH))

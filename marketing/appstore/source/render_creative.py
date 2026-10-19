"""App Store creative assets: product page header (21:9), search results (3:2) and the 16:9 asset that serves both.
Same studio look as the screenshots; focal point centred, one short phrase, no other platforms mentioned."""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_MAC, RAW_IOS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]

# Backdrop, devices and type from the screenshot renderer; the perspective window from the Mac renderer
source = open(os.path.join(HERE, "render_store.py")).read()
exec(compile(source[: source.index("# ─── iPhone")], "render_store.py", "exec"))
mac_source = open(os.path.join(HERE, "render_mac.py")).read()
start = mac_source.index("def place_window")
exec(compile(mac_source[start: mac_source.index("def left_badges")], "render_mac.py", "exec"))

RAW, OUT = RAW_IOS, sys.argv[3]  # the shared code reset both; shot() reads iPhone and iPad captures from RAW
SS = 1  # these canvases are already 4K-plus; supersampling would only cost memory


def headline(canvas, eyebrow, title, top, size):
    d = ImageDraw.Draw(canvas)
    w = canvas.size[0]
    small = font("semibold", size * 0.30)
    big = font("bold", size)
    text = eyebrow.upper()
    spacing = size * 0.05
    total = sum(d.textlength(ch, font=small) + spacing for ch in text) - spacing
    x = (w - total) / 2
    for ch in text:
        d.text((x, top), ch, font=small, fill=SKY)
        x += d.textlength(ch, font=small) + spacing
    y = top + size * 0.62
    for line in title.split("\n"):
        d.text(((w - d.textlength(line, font=big)) / 2, y), line, font=big, fill=WHITE)
        y += size * 1.1


def save(canvas, name):
    canvas.convert("RGB").save(f"{OUT}/{name}.png", optimize=True)
    print("wrote", name, canvas.size)


mac_window = Image.open(f"{RAW_MAC}/m1.png")
iphone = shot("iphone-codes")
ipad = shot("ipad-codes")

# Product page header, 21:9 (3840 × 1646): the three devices as one centred group under a short line
c = backdrop(3840, 1646, glow=(0.5, 0.62))
headline(c, "VaultSpec Authenticator", "Your 2FA codes. Locked down.", 120, 150)
place_window(c, mac_window, 1920, 1010, 1500, yaw=0, pitch=8)
place(c, ipad, "ipad", 1090, 1060, 980, yaw=24, pitch=6, roll=2, depth=0.035, glow=False)
place(c, iphone, "phone", 2760, 1110, 900, yaw=-24, pitch=7, roll=-2, glow=False)
save(c, "header-3840x1646")

# Search results, 3:2 (3840 × 2560): say plainly what it is, with the codes front and centre
c = backdrop(3840, 2560, glow=(0.5, 0.64))
headline(c, "Two-factor authenticator", "Encrypted 2FA codes\nfor iPhone, iPad and Mac", 170, 190)
place_window(c, mac_window, 1920, 1640, 1900, yaw=0, pitch=8)
place(c, iphone, "phone", 2980, 1780, 1250, yaw=-20, pitch=7, roll=-2, glow=False)
place(c, ipad, "ipad", 860, 1760, 1280, yaw=20, pitch=6, roll=2, depth=0.035, glow=False)
save(c, "search-3840x2560")

# One asset for both placements, 16:9 (5244 × 2950)
c = backdrop(5244, 2950, glow=(0.5, 0.62))
headline(c, "VaultSpec Authenticator", "Your 2FA codes. Locked down.", 260, 210)
place_window(c, mac_window, 2622, 1760, 2300, yaw=0, pitch=8)
place(c, ipad, "ipad", 1380, 1860, 1550, yaw=24, pitch=6, roll=2, depth=0.035, glow=False)
place(c, iphone, "phone", 3860, 1930, 1400, yaw=-24, pitch=7, roll=-2, glow=False)
save(c, "universal-5244x2950")

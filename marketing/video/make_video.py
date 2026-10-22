#!/usr/bin/env python3
"""Builds the VaultSpec Authenticator launch video for iPhone, iPad and Mac.

  python marketing/video/make_video.py

Recordings come from the simulator (marketing/video/work/rec): iphone-*.mp4 and ipad-codes.mp4 are
screen recordings of the demo vault; mac-*.png are captures of the Mac app on a desktop.
Narration and captions work like the Android update video (auth-android/promo/make_video.py):
ElevenLabs when ELEVENLABS_API_KEY is set (environment, or marketing/video/.env, or the Android
promo's .env), cached in marketing/video/audio; otherwise a silent, captioned render.

Needs ffmpeg and Pillow. Writes marketing/video/VaultSpec-launch-apple.mp4 (1080×1920).
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
WORK = ROOT / "work"
REC, AUDIO, BUILD = WORK / "rec", ROOT / "audio", WORK / "build"
FONTS = Path("/Volumes/Projects/auth-android/app/src/main/res/font")
OUTPUT = ROOT / "VaultSpec-launch-apple.mp4"

W, H, FPS = 1080, 1920, 30
# iPhone screen inside a titanium body with the Dynamic Island; recordings are 1320×2868
PHONE_W, PHONE_H = 600, 1304
PHONE_X, PHONE_Y, PHONE_R = (W - PHONE_W) // 2, 300, 92
BEZEL, RAIL = 14, 6
BODY = BEZEL + RAIL
# MacBook screen, for the 2048×1331 desktop captures
MAC_W, MAC_H = 980, 638
MAC_X, MAC_Y = (W - MAC_W) // 2, 640
# iPad screen, for 2064×2752 recordings
PAD_W, PAD_H = 900, 1200
PAD_X, PAD_Y, PAD_R = (W - PAD_W) // 2, 360, 34
LEAD, TAIL = 0.35, 0.45
WORDS_PER_SECOND = 2.6
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "nPczCjzI2devNBz1zQrb")  # "Brian", as in the Android video
MODEL_ID = "eleven_multilingual_v2"

ACCENT = (10, 132, 255)
WHITE, GRAY = (255, 255, 255), (174, 174, 180)

# Each scene: headline, narration, optional caption text, and footage as (clip, start, end) seconds.
# kind "phone" (default) plays iPhone footage; "ipad" plays iPad footage; "mac" pans over a still.
SCENES = [
    dict(
        kind="title",
        headline="VaultSpec Authenticator",
        say="VaultSpec Authenticator is now on the App Store, for iPhone, iPad and Mac. "
            "Free, open source, and encrypted on your device.",
    ),
    dict(
        headline="Unlock with Face ID",
        say="Open your vault with Face ID or your vault password. Every code is encrypted on your device.",
        footage=[("iphone-lock", 0.2, 2.6), ("iphone-lock", 3.6, 8.5)],
    ),
    dict(
        headline="Your codes, at a glance",
        say="All your two-factor codes in one clean list, with a live countdown. Tap a code to copy it.",
        footage=[("iphone-codes", 0.2, 7.0)],
    ),
    dict(
        headline="Add any service",
        say="Adding an account takes seconds. Scan the QR code, or paste the setup link from any site.",
        footage=[("iphone-add", 1.4, 6.2)],
    ),
    dict(
        headline="Locked down by default",
        say="Choose when it auto-locks, block screenshots, and hide codes until you tap them.",
        footage=[("iphone-settings", 0.3, 9.5)],
    ),
    dict(
        kind="ipad",
        headline="Made for iPad",
        say="On iPad, your codes spread out into a grid that fits every screen.",
        footage=[("ipad-codes", 0.5, 12.5)],
    ),
    dict(
        kind="mac",
        headline="And now on Mac",
        say="And it's a real Mac app too, with Touch ID and keyboard shortcuts, "
            "right next to the apps you sign in to.",
        stills=["mac-codes", "mac-settings"],
    ),
    dict(
        kind="outro",
        headline="Download now",
        say="Search VaultSpec Authenticator on the App Store and download it today. It's free. "
            "If you like it and want to support my work, you can buy me a coffee at "
            "buy me a coffee dot com, slash dhruvesh sixteen. Thanks for using VaultSpec.",
        caption="Search VaultSpec Authenticator on the App Store and download it today. It's free. "
                "If you like it and want to support my work, you can buy me a coffee at "
                "buymeacoffee.com/dhruvesh16. Thanks for using VaultSpec.",
        hold=1.5,
    ),
]


def run(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *map(str, args)], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         check=True, capture_output=True, text=True)
    return float(out.stdout.strip())


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f"inter_{weight}.ttf"), size)


# ── Narration ──

def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    for file in (ROOT / ".env", Path("/Volumes/Projects/auth-android/promo/.env")):
        if key or not file.exists():
            continue
        for line in file.read_text().splitlines():
            name, _, value = line.strip().partition("=")
            if name.strip().removeprefix("export ").strip() == "ELEVENLABS_API_KEY":
                key = value.strip().strip("\"'")
    return key or None


def narration(index, text, key):
    tag = hashlib.sha256(f"{VOICE_ID}|{MODEL_ID}|{text}".encode()).hexdigest()[:10]
    path = AUDIO / f"{index:02d}_{tag}.mp3"
    if path.exists():
        return path
    if not key:
        return None
    AUDIO.mkdir(exist_ok=True)
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "model_id": MODEL_ID,
                         "voice_settings": {"stability": 0.45, "similarity_boost": 0.8, "style": 0.15}}).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"ElevenLabs returned {e.code} for scene {index}: {e.read().decode(errors='replace')[:300]}")
    print(f"  narration {index:02d}: {duration(path):.1f}s")
    return path


# ── Artwork ──

def background():
    img = Image.new("RGB", (W, H), (9, 9, 12))
    glow = Image.new("RGB", (W, H), (9, 9, 12))
    d = ImageDraw.Draw(glow)
    d.ellipse((-200, 500, W + 200, 1700), fill=(16, 34, 66))
    d.ellipse((180, 80, 900, 620), fill=(20, 24, 44))
    return Image.blend(img, glow.filter(ImageFilter.GaussianBlur(220)), 0.9)


def logo(size, color=WHITE):
    bars = [(21, 34), (27, 42), (33, 52), (39, 62), (45, 72), (51, 78),
            (57, 78), (63, 72), (69, 62), (75, 52), (81, 42), (87, 34)]
    k = 4
    s = size * k / 108
    img = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for cx, h in bars:
        d.rounded_rectangle(((cx - 2) * s, (54 - h / 2) * s, (cx + 2) * s, (54 + h / 2) * s), radius=2 * s, fill=color)
    return img.resize((size, size), Image.LANCZOS)


def app_icon(size):
    """The app icon: white mark on the blue rounded tile, as on the App Store."""
    k = 4
    n = size * k
    tile = Image.new("RGB", (1, n))
    top, bottom = (40, 140, 255), (10, 70, 230)
    for y in range(n):
        t = y / (n - 1)
        tile.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    tile = tile.resize((n, n))
    shape = Image.new("L", (n, n), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.225), fill=255)
    icon = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    icon.paste(tile, (0, 0), shape)
    mark = logo(int(n * 0.66))
    icon.alpha_composite(mark, ((n - mark.width) // 2, (n - mark.height) // 2))
    return icon.resize((size, size), Image.LANCZOS)


def apple_logo(size, color=WHITE):
    """A simple apple silhouette for the "Download on the App Store" badge."""
    k = 4
    n = size * k
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((n * 0.06, n * 0.28, n * 0.56, n * 0.98), fill=color)
    d.ellipse((n * 0.44, n * 0.28, n * 0.94, n * 0.98), fill=color)
    d.ellipse((n * 0.70, n * 0.40, n * 1.08, n * 0.74), fill=(0, 0, 0, 0))  # the bite
    d.ellipse((n * 0.48, n * 0.02, n * 0.68, n * 0.28), fill=color)          # the leaf
    return img.resize((size, size), Image.LANCZOS)


def centered(draw, y, text, fnt, fill):
    draw.text(((W - draw.textlength(text, font=fnt)) / 2, y), text, font=fnt, fill=fill)


def wrap(draw, text, fnt, max_width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line] if line else lines


def store_badge(img, y):
    """A black "Download on the App Store" pill, centred at [y]."""
    d = ImageDraw.Draw(img)
    small, big = font("medium", 26), font("semibold", 50)
    text_w = max(d.textlength("Download on the", font=small), d.textlength("App Store", font=big))
    w, h = int(text_w + 170), 124
    x = (W - w) // 2
    d.rounded_rectangle((x, y, x + w, y + h), radius=28, fill=(0, 0, 0), outline=(160, 160, 168), width=3)
    mark = apple_logo(64)
    img.paste(mark, (x + 40, y + 28), mark)
    d.text((x + 124, y + 20), "Download on the", font=small, fill=WHITE)
    d.text((x + 122, y + 50), "App Store", font=big, fill=WHITE)


def scene_card(scene, path):
    img = background()
    d = ImageDraw.Draw(img)
    kind = scene.get("kind", "phone")
    if kind == "title":
        icon = app_icon(300)
        img.paste(icon, ((W - 300) // 2, 470), icon)
        centered(d, 830, "VaultSpec", font("bold", 104), WHITE)
        centered(d, 950, "Authenticator", font("medium", 60), GRAY)
        pill = "NOW ON THE APP STORE"
        f = font("semibold", 32)
        pw = d.textlength(pill, font=f) + 72
        d.rounded_rectangle(((W - pw) / 2, 1100, (W + pw) / 2, 1176), radius=38, fill=ACCENT)
        centered(d, 1118, pill, f, WHITE)
        centered(d, 1226, "iPhone  ·  iPad  ·  Mac", font("semibold", 34), GRAY)
    elif kind == "outro":
        icon = app_icon(200)
        img.paste(icon, ((W - 200) // 2, 300), icon)
        centered(d, 540, "Download now", font("bold", 84), WHITE)
        centered(d, 650, "Free on iPhone, iPad and Mac", font("medium", 42), GRAY)
        store_badge(img, 760)
        d.rounded_rectangle((110, 960, W - 110, 1240), radius=44, fill=(28, 28, 32))
        centered(d, 1000, "SUPPORT MY WORK", font("semibold", 30), ACCENT)
        centered(d, 1062, "buymeacoffee.com", font("bold", 58), WHITE)
        centered(d, 1138, "/dhruvesh16", font("bold", 58), (255, 184, 77))
    else:
        centered(d, 92, "VAULTSPEC  ·  NOW ON THE APP STORE", font("semibold", 28), ACCENT)
        centered(d, 150, scene["headline"], font("bold", 68), WHITE)
        if kind in ("phone", "ipad"):
            x, y, w, h, r = (PHONE_X, PHONE_Y, PHONE_W, PHONE_H, PHONE_R) if kind == "phone" else (PAD_X, PAD_Y, PAD_W, PAD_H, PAD_R)
            shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(shadow).rounded_rectangle((x - BODY - 6, y - BODY + 18, x + w + BODY + 6, y + h + BODY + 30),
                                                     radius=r + BODY, fill=(0, 0, 0, 170))
            blurred = shadow.filter(ImageFilter.GaussianBlur(28))
            img.paste(blurred, (0, 0), blurred)
        elif kind == "mac":
            macbook(img)
    img.save(path)


def macbook(img):
    """A MacBook drawn behind the screen area: shadow, black bezel with a notch, aluminium base."""
    k = 3
    layer = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y, w, h = MAC_X * k, MAC_Y * k, MAC_W * k, MAC_H * k
    bz, top = 16 * k, 20 * k
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x - 60 * k, y + h, x + w + 60 * k, y + h + 70 * k), radius=30 * k, fill=(0, 0, 0, 200))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(26 * k)))
    d.rounded_rectangle((x - bz, y - top, x + w + bz, y + h + bz + 6 * k), radius=28 * k, fill=(118, 122, 134))
    d.rounded_rectangle((x - bz + 3 * k, y - top + 3 * k, x + w + bz - 3 * k, y + h + bz + 3 * k), radius=26 * k, fill=(6, 6, 8))
    by = y + h + bz + 6 * k
    base_h = 26 * k
    for i in range(base_h):  # aluminium base, light on top and darker underneath
        t = i / base_h
        c = tuple(int(a + (b - a) * t) for a, b in zip((214, 217, 224), (112, 116, 126)))
        inset = int(t * t * 22 * k)
        d.line([(x - 70 * k + inset, by + i), (x + w + 70 * k - inset, by + i)], fill=c)
    d.rounded_rectangle((x + w / 2 - 80 * k, by, x + w / 2 + 80 * k, by + 9 * k), radius=6 * k, fill=(150, 154, 164))
    small = layer.resize((W, H), Image.LANCZOS)
    img.paste(small, (0, 0), small)


def screen_mask(path, w, h, r):
    mask = Image.new("L", (w * 3, h * 3), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * 3 - 1, h * 3 - 1), radius=r * 3, fill=255)
    mask.resize((w, h), Image.LANCZOS).save(path)


def device_frame(path, x, y, w, h, r, island):
    """Titanium rail and black bezel around the screen opening; the Dynamic Island on iPhone."""
    k = 3
    img = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(inset):
        return ((x - inset) * k, (y - inset) * k, (x + w + inset) * k, (y + h + inset) * k)

    edge, rail = (150, 156, 170), (78, 82, 94)
    d.rounded_rectangle(box(BODY), radius=(r + BODY) * k, fill=edge)
    d.rounded_rectangle(box(BODY - 2), radius=(r + BODY - 2) * k, fill=rail)
    d.rounded_rectangle(box(BEZEL), radius=(r + BEZEL) * k, fill=(4, 4, 6))
    opening = Image.new("L", img.size, 255)
    ImageDraw.Draw(opening).rounded_rectangle(box(0), radius=r * k, fill=0)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", img.size, 0), opening))
    if island:
        d = ImageDraw.Draw(img)
        iw, ih, top = w * 0.286, w * 0.084, y + w * 0.025
        d.rounded_rectangle(((x + (w - iw) / 2) * k, top * k, (x + (w + iw) / 2) * k, (top + ih) * k),
                            radius=ih / 2 * k, fill=(0, 0, 0, 255))
    img.resize((W, H), Image.LANCZOS).save(path)


def caption_chunks(text, speech_seconds):
    words, chunks, current = text.split(), [], []
    for word in words:
        current.append(word)
        if len(current) >= 8 or (word[-1] in ".,?!:;" and len(current) >= 4):
            chunks.append(" ".join(current))
            current = []
    if current:
        if chunks and len(current) < 3:
            chunks[-1] += " " + " ".join(current)
        else:
            chunks.append(" ".join(current))
    total = sum(len(c) for c in chunks)
    timed, t = [], LEAD
    for chunk in chunks:
        length = speech_seconds * len(chunk) / total
        timed.append((chunk, t, t + length))
        t += length
    return timed


def caption_image(text, path, card):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font("semibold", 40)
    lines = wrap(d, text, f, W - 140)
    y = (1560 if card else 1700) + (2 - min(len(lines), 2)) * 26
    for line in lines:
        # A soft dark band keeps captions readable over bright footage
        tw = d.textlength(line, font=f)
        d.rounded_rectangle(((W - tw) / 2 - 18, y - 6, (W + tw) / 2 + 18, y + 52), radius=14, fill=(0, 0, 0, 120))
        centered(d, y, line, f, WHITE)
        y += 58
    img.save(path)


# ── Assembly ──

def footage_clip(index, segments, seconds, w, h):
    out = BUILD / f"fg_{index:02d}.mp4"
    total = sum(end - start for _, start, end in segments)
    speed = max(total / seconds, 0.85)
    inputs, parts = [], []
    for n, (clip, start, end) in enumerate(segments):
        inputs += ["-ss", f"{start}", "-t", f"{end - start}", "-i", REC / f"{clip}.mp4"]
        parts.append(f"[{n}:v]scale={w}:{h}:flags=lanczos,setsar=1,fps={FPS}[v{n}]")
    joined = "".join(f"[v{n}]" for n in range(len(segments)))
    graph = ";".join(parts) + (
        f";{joined}concat=n={len(segments)}:v=1:a=0,setpts=PTS/{speed:.4f},fps={FPS},"
        f"tpad=stop_mode=clone:stop_duration={seconds},trim=duration={seconds:.3f}[out]"
    )
    run(*inputs, "-filter_complex", graph, "-map", "[out]", "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", out)
    return out


def mac_clip(index, stills, seconds):
    """Slow push-in across the Mac captures (each a desktop with the app window), with a cross-fade."""
    out = BUILD / f"mac_{index:02d}.mp4"
    each = seconds / len(stills)
    w, h = MAC_W, MAC_H   # 2048×1331 desktop scaled into the MacBook screen
    parts, inputs = [], []
    for n, still in enumerate(stills):
        inputs += ["-loop", "1", "-t", f"{each + 0.6:.2f}", "-framerate", f"{FPS}", "-i", REC / f"{still}.png"]
        frames = int((each + 0.6) * FPS)
        parts.append(
            f"[{n}:v]scale=2400:-1,zoompan=z='1+0.06*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
            f":d={frames}:s={w}x{h}:fps={FPS},setsar=1[m{n}]"
        )
    chain, last = [], "m0"
    for n in range(1, len(stills)):
        chain.append(f"[{last}][m{n}]xfade=transition=fade:duration=0.6:offset={each * n - 0.6 * (n - 1) - 0.3:.2f}[x{n}]")
        last = f"x{n}"
    graph = ";".join(parts + chain) + f";[{last}]trim=duration={seconds:.3f},format=yuv420p[out]"
    run(*inputs, "-filter_complex", graph, "-map", "[out]", "-c:v", "libx264", "-preset", "medium", "-crf", "16", out)
    return out, w, h


def build_scene(index, scene, audio, frames):
    kind = scene.get("kind", "phone")
    card = kind in ("title", "outro")
    speech = duration(audio) if audio else len(scene["say"].split()) / WORDS_PER_SECOND
    seconds = round(LEAD + speech + TAIL + scene.get("hold", 0), 2)

    base = BUILD / f"card_{index:02d}.png"
    scene_card(scene, base)

    inputs = ["-loop", "1", "-t", f"{seconds}", "-framerate", f"{FPS}", "-i", base]
    graph, last, n = [], "0:v", 1
    if kind in ("phone", "ipad"):
        x, y, w, h = (PHONE_X, PHONE_Y, PHONE_W, PHONE_H) if kind == "phone" else (PAD_X, PAD_Y, PAD_W, PAD_H)
        mask, frame = frames[kind]
        fg = footage_clip(index, scene["footage"], seconds, w, h)
        inputs += ["-i", fg, "-loop", "1", "-t", f"{seconds}", "-i", mask, "-loop", "1", "-t", f"{seconds}", "-i", frame]
        graph += [
            f"[{n}:v]format=rgba[fg];[{n + 1}:v]format=gray[mk];[fg][mk]alphamerge[dev]",
            f"[{last}][dev]overlay={x}:{y}[withdev]",
            f"[withdev][{n + 2}:v]overlay=0:0[framed]",
        ]
        last, n = "framed", n + 3
    elif kind == "mac":
        clip, w, h = mac_clip(index, scene["stills"], seconds)
        inputs += ["-i", clip]
        graph.append(f"[{last}][{n}:v]overlay={MAC_X}:{MAC_Y}[withmac]")
        last, n = "withmac", n + 1

    for c, (text, start, end) in enumerate(caption_chunks(scene.get("caption", scene["say"]), speech)):
        png = BUILD / f"cap_{index:02d}_{c:02d}.png"
        caption_image(text, png, card)
        inputs += ["-loop", "1", "-t", f"{seconds}", "-i", png]
        graph.append(f"[{last}][{n}:v]overlay=0:0:enable='between(t,{start:.2f},{end:.2f})'[c{c}]")
        last, n = f"c{c}", n + 1

    graph.append(f"[{last}]fade=t=in:st=0:d=0.3,fade=t=out:st={seconds - 0.3:.2f}:d=0.3,format=yuv420p[v]")
    if audio:
        inputs += ["-i", audio]
        graph.append(f"[{n}:a]adelay={int(LEAD * 1000)}:all=1,apad,atrim=duration={seconds},aresample=44100[a]")
    else:
        inputs += ["-f", "lavfi", "-t", f"{seconds}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
        graph.append(f"[{n}:a]atrim=duration={seconds}[a]")

    out = BUILD / f"scene_{index:02d}.mp4"
    run(*inputs, "-filter_complex", ";".join(graph), "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", f"{FPS}", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-shortest", out)
    print(f"  scene {index:02d} {seconds:5.1f}s  {scene['headline']}")
    return out, seconds


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    key = api_key()
    audio = [narration(i, s["say"], key) for i, s in enumerate(SCENES)]
    voiced = all(audio)
    if not voiced:
        audio = [None] * len(SCENES)
        print("No ElevenLabs key and no cached narration: rendering a silent, captioned video.")

    frames = {}
    for kind, (x, y, w, h, r) in {"phone": (PHONE_X, PHONE_Y, PHONE_W, PHONE_H, PHONE_R),
                                  "ipad": (PAD_X, PAD_Y, PAD_W, PAD_H, PAD_R)}.items():
        mask, frame = BUILD / f"mask_{kind}.png", BUILD / f"frame_{kind}.png"
        screen_mask(mask, w, h, r)
        device_frame(frame, x, y, w, h, r, island=(kind == "phone"))
        frames[kind] = (mask, frame)

    scenes = [build_scene(i, s, audio[i], frames) for i, s in enumerate(SCENES)]
    listing = BUILD / "scenes.txt"
    listing.write_text("".join(f"file '{path}'\n" for path, _ in scenes))
    audio_args = ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "44100", "-c:a", "aac", "-b:a", "192k"] if voiced else ["-c:a", "copy"]
    run("-f", "concat", "-safe", "0", "-i", listing, "-c:v", "copy", *audio_args, "-movflags", "+faststart", OUTPUT)
    total = sum(seconds for _, seconds in scenes)
    print(f"{OUTPUT.name}  {total:.0f}s  {'with narration' if voiced else 'silent'}")


if __name__ == "__main__":
    main()

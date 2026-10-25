#!/usr/bin/env python3
"""VaultSpec Authenticator on iPhone Duo: a short 1080×1920 launch clip, music only.

  python marketing/video/duo/make_music.py        # once: the original background track
  python marketing/video/duo/make_duo_video.py

The footage is duo-fold.mov, a Mac recording of the iPhone Duo simulator running the demo vault (nothing
personal on screen): title card, the Duo folding and opening, closing card. No feature explanations, no
narration and no captions; just the original music from make_music.py. A scene with a "say" line gets
ElevenLabs narration and captions (see ../make_video.py), and the music then ducks under the voice.
No store badge, price or donation link: the video only introduces the app on iPhone Duo.
Layout: all text sits between about y=150 and y=1660 so Reels, Shorts and TikTok overlays don't cover it.
Writes marketing/video/duo/VaultSpec-iPhone-Duo-launch.mp4.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import make_video as mv  # noqa: E402  (shared narration, artwork and caption helpers)

mv.AUDIO = HERE / "audio"
mv.BUILD = HERE / "work" / "build"
REC, MUSIC = HERE / "work" / "rec", HERE / "work" / "music.wav"
OUTPUT = HERE / "VaultSpec-iPhone-Duo-launch.mp4"
W, H, FPS = mv.W, mv.H, mv.FPS
LEAD, TAIL = mv.LEAD, mv.TAIL
WHITE, GRAY, ACCENT = mv.WHITE, mv.GRAY, mv.ACCENT
GREEN, AMBER, VIOLET = (52, 211, 153), (255, 176, 32), (167, 139, 250)

# The Duo's outer screen is 1398×2034 (0.687). Shown 680×990, centred, under the headline block.
SCR_W, SCR_H, SCR_X, SCR_Y, SCR_R = 680, 990, 200, 370, 56
CAPTION_Y = 1540                 # captions end by about y=1660, above the bottom overlays of short-video apps
BEZEL, RAIL = 13, 6
BODY = BEZEL + RAIL
# The fold scene shows the Mac recording of the simulator in a rounded stage panel instead of a device body
FOLD_SRC = HERE / "duo-fold.mov"
FOLD_S, FOLD_X, FOLD_Y, FOLD_R = 960, 60, 470, 52
BG_KEY = "0x1d1d1d"             # the recording's flat background colour; keyed out so the device floats

SCENES = [
    dict(kind="title", headline="VaultSpec Authenticator", min_seconds=4.0,
         say="VaultSpec Authenticator. Built for iPhone Duo."),
    dict(
        kind="fold", headline="Fits your Duo", eyebrow="IPHONE DUO",
        sub="Fold it, open it, rotate it", min_seconds=12.0,
        say="Fold it, open it, rotate it. VaultSpec fits your Duo.",
        # (start, end, centre x, centre y, side) in the 2452x1668 Mac recording; the cuts skip the
        # fold transitions, where the screen goes black, and the stretches with the mouse pointer.
        fold=[(1.5, 2.8, 1222, 860, 950), (17.5, 21.5, 1222, 862, 1290),
              (9.4, 11.0, 1222, 856, 1290), (36.8, 40.0, 1222, 856, 1290)],
    ),
    dict(kind="outro", headline="VaultSpec Authenticator", hold=1.6,
         say="Coming tomorrow. Learn more at vaultspec dot in.",
         caption="Coming tomorrow. Learn more at vaultspec.in."),
]


def split_phrase(text, limit=50):
    """Splits at a comma or conjunction near the middle until every piece fits on one caption line."""
    text = text.strip()
    if len(text) <= limit:
        return [text]
    middle = len(text) / 2
    breaks = [m.end() for m in re.finditer(r",\s+", text)] + [m.start() + 1 for m in re.finditer(r"\s(?:and|or|so|then)\s", text)]
    breaks = [i for i in breaks if 12 <= i <= len(text) - 12] or [i + 1 for i, c in enumerate(text) if c == " " and 12 <= i <= len(text) - 12]
    cut = min(breaks, key=lambda i: abs(i - middle))
    return split_phrase(text[:cut], limit) + split_phrase(text[cut:], limit)


def caption_chunks(text, speech_seconds):
    """(text, start, end) caption pieces: whole sentences or phrases, timed in proportion to their length."""
    pieces = []
    for sentence in re.split(r"(?<=[.!?])\s+", text.strip()):
        pieces += split_phrase(sentence)
    total = sum(len(p) for p in pieces)
    timed, t = [], LEAD
    for piece in pieces:
        length = speech_seconds * len(piece) / total
        timed.append((piece, t, t + length))
        t += length
    return timed


def caption_image(text, path, card):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = mv.font("semibold", 42)
    lines = mv.wrap(d, text.rstrip("."), f, W - 160)
    y = CAPTION_Y + (2 - min(len(lines), 2)) * 30
    for line in lines:
        tw = d.textlength(line, font=f)
        d.rounded_rectangle(((W - tw) / 2 - 20, y - 6, (W + tw) / 2 + 20, y + 54), radius=16, fill=(0, 0, 0, 130))
        mv.centered(d, y, line, f, WHITE)
        y += 64
    img.save(path)


def chip_row(d, y, chips):
    f = mv.font("semibold", 30)
    widths = [d.textlength(t, font=f) + 70 for t, _ in chips]
    x = (W - sum(widths) - 16 * (len(chips) - 1)) / 2
    for (text, color), w in zip(chips, widths):
        d.rounded_rectangle((x, y, x + w, y + 64), radius=32, fill=(14, 22, 48), outline=(70, 105, 200), width=2)
        d.ellipse((x + 24, y + 26, x + 36, y + 38), fill=color)
        d.text((x + 48, y + 14), text, font=f, fill=WHITE)
        x += w + 16


def scene_card(scene, path):
    img = mv.background()
    d = ImageDraw.Draw(img)
    kind = scene.get("kind", "phone")
    if kind == "title":
        icon = mv.app_icon(300)
        img.paste(icon, ((W - 300) // 2, 400), icon)
        mv.centered(d, 760, "VaultSpec", mv.font("bold", 104), WHITE)
        mv.centered(d, 880, "Authenticator", mv.font("medium", 60), GRAY)
        pill, f = "BUILT FOR IPHONE DUO", mv.font("semibold", 32)
        pw = d.textlength(pill, font=f) + 72
        d.rounded_rectangle(((W - pw) / 2, 1020, (W + pw) / 2, 1096), radius=38, fill=ACCENT)
        mv.centered(d, 1038, pill, f, WHITE)
    elif kind == "outro":
        icon = mv.app_icon(220)
        img.paste(icon, ((W - 220) // 2, 330), icon)
        mv.centered(d, 590, "VaultSpec", mv.font("bold", 84), WHITE)
        mv.centered(d, 688, "Authenticator", mv.font("medium", 52), GRAY)
        pill, f = "COMING TOMORROW", mv.font("semibold", 34)
        pw = d.textlength(pill, font=f) + 80
        d.rounded_rectangle(((W - pw) / 2, 800, (W + pw) / 2, 880), radius=40, fill=ACCENT)
        mv.centered(d, 819, pill, f, WHITE)
        d.rounded_rectangle((110, 960, W - 110, 1190), radius=44, fill=(28, 28, 32))
        mv.centered(d, 1004, "LEARN MORE", mv.font("semibold", 30), ACCENT)
        mv.centered(d, 1062, "vaultspec.in", mv.font("bold", 82), WHITE)
    else:
        mv.centered(d, 150, f"VAULTSPEC  ·  {scene['eyebrow']}", mv.font("semibold", 28), ACCENT)
        mv.centered(d, 198, scene["headline"], mv.font("bold", 74), WHITE)
        mv.centered(d, 292, scene["sub"], mv.font("medium", 36), GRAY)
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        if kind == "fold":
            # A blue glow behind the device and a soft floor shadow under it; the device itself is the footage
            cx, cy = FOLD_X + FOLD_S // 2, FOLD_Y + FOLD_S // 2
            glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(glow).ellipse((cx - 470, cy - 360, cx + 470, cy + 360), fill=(20, 80, 220, 95))
            glow = glow.filter(ImageFilter.GaussianBlur(120))
            img.paste(glow, (0, 0), glow)
            ImageDraw.Draw(shadow).ellipse((cx - 330, cy + 400, cx + 330, cy + 450), fill=(0, 0, 0, 200))
            blurred = shadow.filter(ImageFilter.GaussianBlur(24))
            img.paste(blurred, (0, 0), blurred)
        else:
            ImageDraw.Draw(shadow).rounded_rectangle(
                (SCR_X - BODY - 6, SCR_Y - BODY + 20, SCR_X + SCR_W + BODY + 6, SCR_Y + SCR_H + BODY + 32),
                radius=SCR_R + BODY, fill=(0, 0, 0, 170))
            blurred = shadow.filter(ImageFilter.GaussianBlur(30))
            img.paste(blurred, (0, 0), blurred)
    img.save(path)


def device_frame(path):
    """Titanium rail and black bezel around the screen opening (the camera is part of the footage)."""
    k = 3
    img = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(inset):
        return ((SCR_X - inset) * k, (SCR_Y - inset) * k, (SCR_X + SCR_W + inset) * k, (SCR_Y + SCR_H + inset) * k)

    d.rounded_rectangle(box(BODY), radius=(SCR_R + BODY) * k, fill=(150, 156, 170))
    d.rounded_rectangle(box(BODY - 2), radius=(SCR_R + BODY - 2) * k, fill=(78, 82, 94))
    d.rounded_rectangle(box(BEZEL), radius=(SCR_R + BEZEL) * k, fill=(4, 4, 6))
    opening = Image.new("L", img.size, 255)
    ImageDraw.Draw(opening).rounded_rectangle(box(0), radius=SCR_R * k, fill=0)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", img.size, 0), opening))
    img.resize((W, H), Image.LANCZOS).save(path)


def build_scene(index, scene, audio, mask, frame):
    kind = scene.get("kind", "phone")
    card = kind in ("title", "outro")
    if scene.get("say"):
        speech = mv.duration(audio) if audio else len(scene["say"].split()) / mv.WORDS_PER_SECOND
        seconds = round(max(LEAD + speech + TAIL + scene.get("hold", 0), scene.get("min_seconds", 0)), 2)
    else:
        speech, seconds = 0, scene["seconds"]

    base = mv.BUILD / f"card_{index:02d}.png"
    scene_card(scene, base)
    inputs = ["-loop", "1", "-t", f"{seconds}", "-framerate", f"{FPS}", "-i", base]
    graph, last, n = [], "0:v", 1
    if card:   # a slow push-in so the title and closing cards aren't static
        graph.append(f"[0:v]scale=w='{W}*(1+0.05*t/{seconds})':h=-2:eval=frame,crop={W}:{H}[zoom]")
        last = "zoom"
    if kind == "fold":
        out = mv.BUILD / f"fg_{index:02d}.mp4"
        segs = scene["fold"]
        total = sum(e - s for s, e, *_ in segs)
        speed = max(total / seconds, 0.85)
        fin, parts = [], []
        for k, (s, e, cx, cy, side) in enumerate(segs):
            fin += ["-ss", f"{s}", "-t", f"{e - s}", "-i", FOLD_SRC]
            parts.append(f"[{k}:v]crop={side}:{side}:{cx - side // 2}:{max(0, cy - side // 2)},"
                         f"scale={FOLD_S}:{FOLD_S}:flags=lanczos,setsar=1,fps={FPS}[v{k}]")
        joined = "".join(f"[v{k}]" for k in range(len(segs)))
        mv.run(*fin, "-filter_complex", ";".join(parts) + (
            f";{joined}concat=n={len(segs)}:v=1:a=0,setpts=PTS/{speed:.4f},fps={FPS},"
            f"tpad=stop_mode=clone:stop_duration={seconds},trim=duration={seconds:.3f}[out]"),
            "-map", "[out]", "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", out)
        inputs += ["-i", out]
        graph += [
            f"[{n}:v]format=rgba,colorkey={BG_KEY}:0.05:0.03[dev]",
            f"[{last}][dev]overlay={FOLD_X}:{FOLD_Y}[framed]",
        ]
        last, n = "framed", n + 1
    elif not card:
        out = mv.BUILD / f"fg_{index:02d}.mp4"
        segs = scene["footage"]
        total = sum(e - s for _, s, e in segs)
        speed = max(total / seconds, 0.85)
        fin, parts = [], []
        for k, (clip, s, e) in enumerate(segs):
            fin += ["-ss", f"{s}", "-t", f"{e - s}", "-i", REC / f"{clip}.mp4"]
            parts.append(f"[{k}:v]scale={SCR_W}:{SCR_H}:flags=lanczos,setsar=1,fps={FPS}[v{k}]")
        joined = "".join(f"[v{k}]" for k in range(len(segs)))
        mv.run(*fin, "-filter_complex", ";".join(parts) + (
            f";{joined}concat=n={len(segs)}:v=1:a=0,setpts=PTS/{speed:.4f},fps={FPS},"
            f"tpad=stop_mode=clone:stop_duration={seconds},trim=duration={seconds:.3f}[out]"),
            "-map", "[out]", "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", out)
        inputs += ["-i", out, "-loop", "1", "-t", f"{seconds}", "-i", mask, "-loop", "1", "-t", f"{seconds}", "-i", frame]
        graph += [
            f"[{n}:v]format=rgba[fg];[{n + 1}:v]format=gray[mk];[fg][mk]alphamerge[dev]",
            f"[{last}][dev]overlay={SCR_X}:{SCR_Y}[withdev]",
            f"[withdev][{n + 2}:v]overlay=0:0[framed]",
        ]
        last, n = "framed", n + 3

    for c, (text, start, end) in enumerate(caption_chunks(scene.get("caption", scene["say"]), speech) if scene.get("say") else []):
        png = mv.BUILD / f"cap_{index:02d}_{c:02d}.png"
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

    out = mv.BUILD / f"scene_{index:02d}.mp4"
    mv.run(*inputs, "-filter_complex", ";".join(graph), "-map", "[v]", "-map", "[a]",
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", f"{FPS}", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-shortest", out)
    print(f"  scene {index:02d} {seconds:5.1f}s  {scene['headline']}")
    return out, seconds


def main():
    mv.BUILD.mkdir(parents=True, exist_ok=True)
    key = mv.api_key()
    audio = [mv.narration(i, s["say"], key) if s.get("say") else None for i, s in enumerate(SCENES)]
    voiced = any(s.get("say") for s in SCENES)
    if voiced and not all(a for a, s in zip(audio, SCENES) if s.get("say")):
        audio = [None] * len(SCENES)
        voiced = False
        print("No ElevenLabs key and no cached narration: rendering without a voice.")

    mask, frame = mv.BUILD / "mask.png", mv.BUILD / "frame.png"
    mv.screen_mask(mask, SCR_W, SCR_H, SCR_R)
    device_frame(frame)
    scenes = [build_scene(i, s, audio[i], mask, frame) for i, s in enumerate(SCENES)]
    listing = mv.BUILD / "scenes.txt"
    listing.write_text("".join(f"file '{path}'\n" for path, _ in scenes))
    total = sum(seconds for _, seconds in scenes)

    joined = mv.BUILD / "joined.mp4"
    mv.run("-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined)

    if voiced and MUSIC.exists():
        # Music under the voice: the narration (level-matched) triggers a sidechain that ducks the music
        graph = (
            "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11,asplit=2[voice][key];"
            f"[1:a]atrim=duration={total:.2f},asetpts=PTS-STARTPTS,volume=0.62,"
            f"afade=t=in:d=1.0,afade=t=out:st={total - 3:.2f}:d=3[mus];"
            "[mus][key]sidechaincompress=threshold=0.02:ratio=9:attack=25:release=500:makeup=1[duck];"
            "[duck][voice]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.95[a]"
        )
        mv.run("-i", joined, "-i", MUSIC, "-filter_complex", graph, "-map", "0:v", "-map", "[a]",
               "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-movflags", "+faststart", OUTPUT)
    elif MUSIC.exists():
        # No voice: the music is the whole soundtrack, faded in and out and levelled for streaming
        graph = (f"[1:a]atrim=duration={total:.2f},asetpts=PTS-STARTPTS,afade=t=in:d=1.0,"
                 f"afade=t=out:st={total - 3:.2f}:d=3,loudnorm=I=-16:TP=-1.5:LRA=11[a]")
        mv.run("-i", joined, "-i", MUSIC, "-filter_complex", graph, "-map", "0:v", "-map", "[a]",
               "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-movflags", "+faststart", OUTPUT)
    else:
        mv.run("-i", joined, "-c", "copy", "-movflags", "+faststart", OUTPUT)
    print(f"{OUTPUT.name}  {total:.0f}s  {'with narration and music' if voiced and MUSIC.exists() else 'music only' if MUSIC.exists() else 'no music'}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""VaultSpec Authenticator on iPhone Duo: a 1080×1920 launch video with narration, captions and music.

  python marketing/video/duo/make_music.py        # once: the original background track
  python marketing/video/duo/make_duo_video.py

Footage is in marketing/video/duo/work/rec: screen recordings of the outer display of the iPhone Duo
simulator running the demo vault (nothing personal on screen). Narration is ElevenLabs when a key is
available (see ../make_video.py), cached in duo/audio; otherwise a silent, captioned render. The music
is mixed under the voice and ducks whenever the narrator speaks.
Writes marketing/video/duo/VaultSpec-iPhone-Duo-launch.mp4.
"""
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

# The Duo's outer screen is 1398×2034 (0.687). Shown 810×1178, centred, under the headline block.
SCR_W, SCR_H, SCR_X, SCR_Y, SCR_R = 810, 1178, 135, 350, 66
BEZEL, RAIL = 13, 6
BODY = BEZEL + RAIL
# The fold scene shows the Mac recording of the simulator in a rounded stage panel instead of a device body
FOLD_SRC = HERE / "duo-fold.mov"
FOLD_S, FOLD_X, FOLD_Y, FOLD_R = 960, 60, 420, 52
STAGE = (29, 29, 29)             # the recording's own background, so the crop blends into the panel

SCENES = [
    dict(
        kind="title", headline="VaultSpec Authenticator",
        say="VaultSpec Authenticator is now on the App Store, and it's built for iPhone Duo. "
            "Free, open source, and encrypted on your device.",
    ),
    dict(
        headline="Every code at a glance", eyebrow="YOUR CODES",
        sub="One clean list with a live countdown",
        chips=[("Live countdown", ACCENT), ("Tap to copy", GREEN), ("Works offline", VIOLET)],
        say="All your two-factor codes in one clean list, with a live countdown. Tap a code to copy it.",
        footage=[("duo-codes", 0.3, 12.0)],
    ),
    dict(
        headline="Add any service", eyebrow="SET UP IN SECONDS",
        sub="Scan a QR code or paste a setup link",
        chips=[("QR or setup key", ACCENT), ("6 or 8 digits", VIOLET), ("SHA-1, 256, 512", GREEN)],
        say="Adding an account takes seconds. Scan the QR code, or paste the setup link or key from any site.",
        footage=[("duo-add", 0.4, 5.8)],
    ),
    dict(
        headline="Locked down by default", eyebrow="SECURITY CONTROLS",
        sub="You decide how and when it locks",
        chips=[("Auto-Lock", AMBER), ("Block screenshots", GREEN), ("Tap to reveal", ACCENT)],
        say="Choose when it auto-locks, block screenshots, and hide your codes until you tap them.",
        footage=[("duo-add", 6.3, 10.1)],
    ),
    dict(
        kind="fold", headline="Fits your Duo", eyebrow="IPHONE DUO",
        sub="Fold it, open it, rotate it",
        chips=[("Upright: one column", ACCENT), ("Open: a full grid", GREEN), ("Any orientation", VIOLET)],
        say="On iPhone Duo, VaultSpec fits the way you hold it. Held upright, you get a clean single column. "
            "Turn it, open it up, and your codes spread out into a grid.",
        # (start, end, centre x, centre y, side) in the 2452x1668 Mac recording; the cuts skip the
        # fold transitions, where the screen goes black, and the stretches with the mouse pointer.
        fold=[(1.5, 2.8, 1222, 860, 1040), (17.5, 21.5, 1222, 862, 1380),
              (9.4, 11.0, 1222, 856, 1380), (36.8, 40.0, 1222, 856, 1380)],
    ),
    dict(
        kind="outro", headline="Download now",
        say="Search VaultSpec Authenticator on the App Store and download it today. It's free. "
            "If you like it and want to support my work, you can buy me a coffee at "
            "buy me a coffee dot com, slash dhruvesh sixteen. Thanks for using VaultSpec.",
        caption="Search VaultSpec Authenticator on the App Store and download it today. It's free. "
                "If you like it and want to support my work, you can buy me a coffee at "
                "buymeacoffee.com/dhruvesh16. Thanks for using VaultSpec.",
        hold=1.5,
    ),
]


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
        img.paste(icon, ((W - 300) // 2, 440), icon)
        mv.centered(d, 800, "VaultSpec", mv.font("bold", 104), WHITE)
        mv.centered(d, 920, "Authenticator", mv.font("medium", 60), GRAY)
        pill, f = "NOW ON THE APP STORE", mv.font("semibold", 32)
        pw = d.textlength(pill, font=f) + 72
        d.rounded_rectangle(((W - pw) / 2, 1070, (W + pw) / 2, 1146), radius=38, fill=ACCENT)
        mv.centered(d, 1088, pill, f, WHITE)
        mv.centered(d, 1210, "Built for iPhone Duo", mv.font("bold", 54), WHITE)
        mv.centered(d, 1284, "iPhone  ·  iPad  ·  Mac", mv.font("semibold", 32), GRAY)
    elif kind == "outro":
        icon = mv.app_icon(200)
        img.paste(icon, ((W - 200) // 2, 300), icon)
        mv.centered(d, 540, "Download now", mv.font("bold", 84), WHITE)
        mv.centered(d, 650, "Free on iPhone, iPad and Mac", mv.font("medium", 42), GRAY)
        mv.store_badge(img, 760)
        d.rounded_rectangle((110, 960, W - 110, 1240), radius=44, fill=(28, 28, 32))
        mv.centered(d, 1000, "SUPPORT MY WORK", mv.font("semibold", 30), ACCENT)
        mv.centered(d, 1062, "buymeacoffee.com", mv.font("bold", 58), WHITE)
        mv.centered(d, 1138, "/dhruvesh16", mv.font("bold", 58), (255, 184, 77))
    else:
        mv.centered(d, 84, f"VAULTSPEC  ·  {scene['eyebrow']}", mv.font("semibold", 28), ACCENT)
        mv.centered(d, 134, scene["headline"], mv.font("bold", 76), WHITE)
        mv.centered(d, 232, scene["sub"], mv.font("medium", 36), GRAY)
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        if kind == "fold":
            ImageDraw.Draw(shadow).rounded_rectangle(
                (FOLD_X - 6, FOLD_Y + 20, FOLD_X + FOLD_S + 6, FOLD_Y + FOLD_S + 34), radius=FOLD_R, fill=(0, 0, 0, 170))
            blurred = shadow.filter(ImageFilter.GaussianBlur(30))
            img.paste(blurred, (0, 0), blurred)
            d = ImageDraw.Draw(img)
            d.rounded_rectangle((FOLD_X, FOLD_Y, FOLD_X + FOLD_S, FOLD_Y + FOLD_S), radius=FOLD_R, fill=STAGE,
                                outline=(70, 78, 98), width=3)
            chip_row(d, FOLD_Y + FOLD_S + 38, scene["chips"])
        else:
            ImageDraw.Draw(shadow).rounded_rectangle(
                (SCR_X - BODY - 6, SCR_Y - BODY + 20, SCR_X + SCR_W + BODY + 6, SCR_Y + SCR_H + BODY + 32),
                radius=SCR_R + BODY, fill=(0, 0, 0, 170))
            blurred = shadow.filter(ImageFilter.GaussianBlur(30))
            img.paste(blurred, (0, 0), blurred)
            chip_row(d, SCR_Y + SCR_H + BODY + 34, scene["chips"])
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
    speech = mv.duration(audio) if audio else len(scene["say"].split()) / mv.WORDS_PER_SECOND
    seconds = round(LEAD + speech + TAIL + scene.get("hold", 0), 2)

    base = mv.BUILD / f"card_{index:02d}.png"
    scene_card(scene, base)
    inputs = ["-loop", "1", "-t", f"{seconds}", "-framerate", f"{FPS}", "-i", base]
    graph, last, n = [], "0:v", 1
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
        fmask = mv.BUILD / "mask_fold.png"
        mv.screen_mask(fmask, FOLD_S, FOLD_S, FOLD_R)
        inputs += ["-i", out, "-loop", "1", "-t", f"{seconds}", "-i", fmask]
        graph += [
            f"[{n}:v]format=rgba[fg];[{n + 1}:v]format=gray[mk];[fg][mk]alphamerge[stage]",
            f"[{last}][stage]overlay={FOLD_X}:{FOLD_Y}[framed]",
        ]
        last, n = "framed", n + 2
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

    for c, (text, start, end) in enumerate(mv.caption_chunks(scene.get("caption", scene["say"]), speech)):
        png = mv.BUILD / f"cap_{index:02d}_{c:02d}.png"
        mv.caption_image(text, png, card)
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
    audio = [mv.narration(i, s["say"], key) for i, s in enumerate(SCENES)]
    voiced = all(audio)
    if not voiced:
        audio = [None] * len(SCENES)
        print("No ElevenLabs key and no cached narration: rendering a silent, captioned video.")

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
            f"[1:a]atrim=duration={total:.2f},asetpts=PTS-STARTPTS,volume=0.36[mus];"
            "[mus][key]sidechaincompress=threshold=0.02:ratio=9:attack=25:release=500:makeup=1[duck];"
            "[duck][voice]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.95[a]"
        )
        mv.run("-i", joined, "-i", MUSIC, "-filter_complex", graph, "-map", "0:v", "-map", "[a]",
               "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-movflags", "+faststart", OUTPUT)
    else:
        mv.run("-i", joined, "-c", "copy", "-movflags", "+faststart", OUTPUT)
    print(f"{OUTPUT.name}  {total:.0f}s  {'with narration and music' if voiced and MUSIC.exists() else 'no music'}")


if __name__ == "__main__":
    main()

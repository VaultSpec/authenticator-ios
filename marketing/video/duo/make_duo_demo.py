#!/usr/bin/env python3
"""VaultSpec Authenticator on iPhone Duo: a screen-recording demo, title card plus music, no narration.

  python marketing/video/duo/make_duo_demo.py

Footage: two Mac recordings of the iPhone Duo simulator (SIGNIN, DEMO below), cropped to the device. Anything
personal is blurred: the email and password fields, the account rows and subtitles, the verification and
TOTP codes. The first title card is the only text; the music is make_music.py's original track.
Writes marketing/video/duo/VaultSpec-iPhone-Duo-demo.mp4.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import make_video as mv  # noqa: E402

BUILD, MUSIC = HERE / "work" / "build-demo", HERE / "work" / "music.wav"
OUTPUT = HERE / "VaultSpec-iPhone-Duo-demo.mp4"
W, H, FPS = mv.W, mv.H, mv.FPS
WHITE, GRAY, ACCENT = mv.WHITE, mv.GRAY, mv.ACCENT
SIGNIN = Path("/Volumes/Projects/partner-demo/Screen Recording 2026-10-27 at 12.14.00.mov")
DEMO = Path("/Volumes/Projects/partner-demo/Screen Recording 2026-10-27 at 12.17.25.mov")
BG_KEY = "0x1d1d1d"
DEV_W, DEV_H, DEV_X, DEV_Y = 648, 900, 580, None   # the device's box inside each recording
STAGE_W, STAGE_H, STAGE_X, STAGE_Y = 864, 1200, 108, 380
TITLE_SECONDS = 4.0

# (recording, crop y, start, end, speed, blur boxes (x, y, w, h) in device pixels)
FIELDS = (60, 245, 465, 145)           # email and password fields on Sign In
CHECK = (60, 190, 465, 135)           # verification code field and the "we sent a code to ..." line
ACCOUNT = (60, 128, 465, 135)         # account row on Restore from Cloud
RESTORE_PW = (60, 300, 465, 75)
SUBTITLES = [(150, 258, 260, 30), (150, 462, 260, 30)]   # card subtitles carry real emails
CODE = (75, 300, 225, 75)
CLIPS = [
    (SIGNIN, 32, 25, 41, 1.8, [FIELDS, CHECK]),
    (SIGNIN, 32, 41, 46, 1.4, [CHECK]),
    (SIGNIN, 32, 56, 61, 1.4, [CHECK]),
    (SIGNIN, 32, 62, 75, 1.6, [ACCOUNT, RESTORE_PW]),
    (DEMO, 160, 18, 23.5, 1.1, SUBTITLES),
    (DEMO, 160, 40, 43.2, 1.0, []),
    (DEMO, 160, 52, 56, 1.2, []),
    (DEMO, 160, 56, 62, 1.0, SUBTITLES),
    (DEMO, 160, 62, 68, 1.0, SUBTITLES + [CODE]),
]


def title_card(path):
    img = mv.background()
    d = ImageDraw.Draw(img)
    icon = mv.app_icon(300)
    img.paste(icon, ((W - 300) // 2, 400), icon)
    mv.centered(d, 760, "VaultSpec", mv.font("bold", 104), WHITE)
    mv.centered(d, 880, "Authenticator", mv.font("medium", 60), GRAY)
    pill, f = "FOR IPHONE DUO", mv.font("semibold", 32)
    pw = d.textlength(pill, font=f) + 72
    d.rounded_rectangle(((W - pw) / 2, 1020, (W + pw) / 2, 1096), radius=38, fill=ACCENT)
    mv.centered(d, 1038, pill, f, WHITE)
    img.save(path)


def stage_card(path):
    img = mv.background()
    d = ImageDraw.Draw(img)
    mv.centered(d, 160, "VAULTSPEC AUTHENTICATOR", mv.font("semibold", 30), ACCENT)
    mv.centered(d, 214, "for iPhone Duo", mv.font("bold", 64), WHITE)
    img.save(path)


def title_clip(path):
    card = BUILD / "title.png"
    title_card(card)
    mv.run("-loop", "1", "-t", f"{TITLE_SECONDS}", "-framerate", f"{FPS}", "-i", card, "-filter_complex",
           f"[0:v]scale=w='{W}*(1+0.05*t/{TITLE_SECONDS})':h=-2:eval=frame,crop={W}:{H},"
           f"fade=t=in:st=0:d=0.4,fade=t=out:st={TITLE_SECONDS - 0.4}:d=0.4,format=yuv420p[v]",
           "-map", "[v]", "-c:v", "libx264", "-crf", "18", "-r", f"{FPS}", "-pix_fmt", "yuv420p", path)


def footage_clip(i, clip, stage):
    src, cy, s, e, speed, blurs = clip
    seconds = (e - s) / speed
    graph = [f"[0:v]crop={DEV_W}:{DEV_H}:{DEV_X}:{cy},setsar=1[d0]"]
    last = "d0"
    for k, (x, y, w, h) in enumerate(blurs):
        graph.append(f"[{last}]split[a{k}][b{k}];[b{k}]crop={w}:{h}:{x}:{y},gblur=sigma=16:steps=3[bl{k}];"
                     f"[a{k}][bl{k}]overlay={x}:{y}[d{k + 1}]")
        last = f"d{k + 1}"
    graph.append(f"[{last}]scale={STAGE_W}:{STAGE_H}:flags=lanczos,format=rgba,colorkey={BG_KEY}:0.05:0.03,"
                 f"setpts=PTS/{speed},fps={FPS}[dev]")
    graph.append(f"[1:v][dev]overlay={STAGE_X}:{STAGE_Y}:shortest=1,"
                 f"fade=t=in:st=0:d=0.2,fade=t=out:st={seconds - 0.2:.2f}:d=0.2,format=yuv420p[v]")
    out = BUILD / f"clip_{i:02d}.mp4"
    mv.run("-ss", f"{s}", "-t", f"{e - s}", "-i", src, "-loop", "1", "-framerate", f"{FPS}", "-i", stage,
           "-filter_complex", ";".join(graph), "-map", "[v]", "-t", f"{seconds:.3f}", "-c:v", "libx264",
           "-crf", "17", "-r", f"{FPS}", "-pix_fmt", "yuv420p", out)
    return out, seconds


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    stage = BUILD / "stage.png"
    stage_card(stage)
    title = BUILD / "title.mp4"
    title_clip(title)
    parts, total = [title], TITLE_SECONDS
    for i, clip in enumerate(CLIPS):
        path, seconds = footage_clip(i, clip, stage)
        parts.append(path)
        total += seconds
        print(f"  clip {i} {seconds:5.1f}s")
    listing = BUILD / "clips.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    joined = BUILD / "joined.mp4"
    mv.run("-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined)
    graph = (f"[1:a]atrim=duration={total:.2f},asetpts=PTS-STARTPTS,afade=t=in:d=1.0,"
             f"afade=t=out:st={total - 3:.2f}:d=3,loudnorm=I=-16:TP=-1.5:LRA=11[a]")
    mv.run("-i", joined, "-i", MUSIC, "-filter_complex", graph, "-map", "0:v", "-map", "[a]", "-c:v", "copy",
           "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-movflags", "+faststart", OUTPUT)
    print(f"{OUTPUT.name}  {total:.0f}s")


if __name__ == "__main__":
    main()

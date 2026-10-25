#!/usr/bin/env python3
"""An original background track for the iPhone Duo launch video: warm pad, soft arpeggio, light pulse.

  python marketing/video/duo/make_music.py [seconds]

Synthesised from scratch with NumPy (no samples, no third-party music), so there's nothing to license.
96 BPM, A minor (Am - F - C - G); the pulse comes in after two bars and the end fades out.
Writes marketing/video/duo/work/music.wav (44.1 kHz stereo).
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
OUT = Path(__file__).resolve().parent / "work" / "music.wav"

# Chord roots (MIDI) and the notes of each chord, one per bar
CHORDS = [(45, [57, 60, 64]), (41, [53, 57, 60]), (48, [55, 60, 64]), (43, [55, 59, 62])]  # Am F C G


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env_adsr(n, attack, release):
    e = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    if a:
        e[:a] = np.linspace(0, 1, a) ** 1.5
    if r:
        e[-r:] *= np.linspace(1, 0, r) ** 1.5
    return e


def add(track, start, sound):
    # Fade every sound's last 8 ms so nothing ends on a click
    tail = min(sound.shape[1], int(0.008 * SR))
    sound = sound.copy()
    sound[:, -tail:] *= np.linspace(1, 0, tail)
    i = int(start * SR)
    if i >= len(track[0]):
        return
    j = min(len(track[0]), i + sound.shape[1])
    track[:, i:j] += sound[:, : j - i]


def pad(freqs, dur):
    """Soft detuned stack of sines with a few harmonics, slightly wider on the right."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    left = np.zeros(n)
    right = np.zeros(n)
    for f in freqs:
        for k, amp in ((1, 1.0), (2, 0.35), (3, 0.12)):
            left += amp * np.sin(2 * np.pi * f * k * 0.9985 * t)
            right += amp * np.sin(2 * np.pi * f * k * 1.0015 * t + 0.4)
    e = env_adsr(n, 1.1, 1.4)
    out = np.stack([left, right]) * e
    return out * 0.05 / max(1, len(freqs) / 3)


def pluck(freq, dur=0.9, pan=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t * 9) + 0.15 * np.sin(2 * np.pi * freq * 3 * t)
    tone *= np.exp(-t * 4.2) * (1 - np.exp(-t * 400))
    left, right = (1 - pan) / 2 + 0.5, (1 + pan) / 2 + 0.5
    return np.stack([tone * left, tone * right]) * 0.11


def kick():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    freq = 46 + 90 * np.exp(-t * 28)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = np.sin(phase) * np.exp(-t * 11)
    return np.stack([tone, tone]) * 0.30


def hat(seed):
    n = int(0.06 * SR)
    noise = np.random.default_rng(seed).standard_normal(n)
    noise = np.diff(noise, prepend=0)            # crude high-pass
    noise = np.convolve(noise, np.ones(3) / 3, mode="same")   # take the harshest top end off
    out = noise * np.exp(-np.arange(n) / SR * 70) * (1 - np.exp(-np.arange(n) / SR * 800))
    return np.stack([out, out]) * 0.022


def bass(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    tone *= env_adsr(n, 0.02, 0.25)
    return np.stack([tone, tone]) * 0.16


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 76.0
    total = int(seconds * SR)
    track = np.zeros((2, total + 6 * SR))
    bars = int(seconds / BAR) + 2
    for bar in range(bars):
        root, notes = CHORDS[bar % 4]
        start = bar * BAR
        add(track, start, pad([hz(n) for n in notes] + [hz(root)], BAR + 1.2))
        # eighth-note arpeggio over the chord, an octave up on every other bar
        shape = [0, 1, 2, 1, 0, 2, 1, 2]
        for step, idx in enumerate(shape):
            note = notes[idx] + (12 if bar % 2 else 0)
            add(track, start + step * BEAT / 2, pluck(hz(note), pan=(-0.25 if step % 2 else 0.25)))
        if bar >= 2:                               # the pulse comes in after two bars
            for beat in range(4):
                add(track, start + beat * BEAT, kick())
                add(track, start + beat * BEAT + BEAT / 2, hat(bar * 8 + beat))
            add(track, start, bass(hz(root), BEAT * 1.8))
            add(track, start + 2 * BEAT, bass(hz(root), BEAT * 1.8))

    track = track[:, :total]
    fade_in, fade_out = int(2.5 * SR), int(5.0 * SR)
    track[:, :fade_in] *= np.linspace(0, 1, fade_in) ** 1.5
    track[:, -fade_out:] *= np.linspace(1, 0, fade_out) ** 1.5
    track = np.tanh(track * 1.4) / 1.4              # gentle saturation to glue it together
    track /= max(1e-6, np.abs(track).max()) / 0.85

    OUT.parent.mkdir(parents=True, exist_ok=True)
    pcm = (track.T * 32767).astype("<i2")
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{OUT.name}  {seconds:.0f}s  {BPM} BPM")


if __name__ == "__main__":
    main()

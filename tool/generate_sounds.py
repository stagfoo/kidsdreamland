#!/usr/bin/env python3
"""Generates the sound effects in assets/sounds/.

One sonic palette — soft marimba and bells — synthesised rather than
sourced, so the whole set genuinely shares a timbre instead of being a bag
of downloads that happen to be free, and so it can be retuned by changing
a number here rather than by finding new samples.

Everything is short and mono. These fire constantly (the draw sound loops
while a finger drags), so latency and size matter more than fidelity;
22.05kHz mono is well past enough for a tablet speaker and keeps the whole
set under 100KB.

Run:  python3 tool/generate_sounds.py
"""

import math
import os
import struct
import wave

import numpy as np

RATE = 22050


def env_perc(n, attack=0.004, decay=0.25, curve=3.0):
    """A percussive envelope: near-instant attack, exponential decay.

    The fast attack is what makes a sound feel like it happened *when*
    you touched, rather than just after — the single thing that separates
    a responsive button from a laggy one, at a scale no one consciously
    notices.
    """
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-6), 0, 1)
    d = np.exp(-t / decay * curve)
    return a * d


def tone(freq, n, harmonics=((1, 1.0),), detune=0.0):
    """A sum of harmonics. Marimba-ish: a strong fundamental with a quiet
    partial a couple of octaves up, which is what gives it wood rather
    than flute."""
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for mult, amp in harmonics:
        f = freq * mult * (1 + detune)
        out += amp * np.sin(2 * math.pi * f * t)
    return out


def noise(n, seed):
    return np.random.default_rng(seed).normal(0, 1, n)


def lowpass(x, cutoff):
    """A one-pole lowpass. Enough to take the fizz off white noise and
    turn it into something closer to paper or water."""
    a = math.exp(-2 * math.pi * cutoff / RATE)
    out = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = a * acc + (1 - a) * v
        out[i] = acc
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def normalise(x, peak=0.85):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def fade_edges(x, ms=4):
    """Both ends taper to zero. A sample that starts or ends on a non-zero
    value clicks, and a click on a sound that fires hundreds of times is
    the thing that makes an app feel cheap."""
    n = int(RATE * ms / 1000)
    if len(x) < 2 * n:
        return x
    ramp = np.linspace(0, 1, n)
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def write(name, samples):
    s = fade_edges(normalise(np.asarray(samples, dtype=float)))
    pcm = np.clip(s, -1, 1)
    data = (pcm * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"  {name:16s} {len(s)/RATE*1000:5.0f}ms  {len(data)//1024:3d}KB")


# --------------------------------------------------------------- the set

def sfx_tap():
    """A short wooden blip. C6-ish, so it sits above the music of a room
    and under a shriek."""
    n = int(RATE * 0.16)
    body = tone(1046.5, n, harmonics=((1, 1.0), (3.9, 0.22), (9.2, 0.06)))
    # A touch of noise at the very front reads as the mallet hitting.
    click = noise(n, 1) * np.exp(-np.arange(n) / RATE / 0.004)
    return (body * env_perc(n, decay=0.10) + click * 0.12)


def sfx_color():
    """The same voice as the tap but rounder and longer — picking a colour
    is a bigger event than pressing a button, and the app pitches this one
    per colour to make the palette an instrument."""
    n = int(RATE * 0.30)
    body = tone(523.25, n, harmonics=((1, 1.0), (4.0, 0.30), (10.0, 0.08)))
    return body * env_perc(n, decay=0.16)


def sfx_draw():
    """Soft pencil scratch. Filtered noise, no pitch — it loops under a
    dragging finger, and anything tonal would turn into a drone."""
    n = int(RATE * 0.12)
    grain = highpass(lowpass(noise(n, 2), 2600), 700)
    # A gentle swell rather than a percussive hit: it is a continuous
    # sound being sampled, not an event.
    t = np.arange(n) / n
    return grain * np.sin(math.pi * t) * 0.9


def sfx_fill():
    """A little sploosh. A pitch sweeping downward through filtered noise
    is the cheapest convincing 'liquid arriving' there is."""
    n = int(RATE * 0.34)
    t = np.arange(n) / RATE
    sweep = np.sin(2 * math.pi * np.cumsum(np.linspace(900, 260, n)) / RATE)
    wet = lowpass(noise(n, 3), 1800) * 0.7
    return (sweep * 0.7 + wet) * env_perc(n, decay=0.13)


def sfx_complete():
    """The celebration: a major arpeggio on the marimba voice, four notes
    rising. The only sound in the set that means something was achieved,
    so it is the longest and the only one never pitch-jittered."""
    notes = [523.25, 659.25, 783.99, 1046.50]  # C E G C
    gap = int(RATE * 0.085)
    n = gap * len(notes) + int(RATE * 0.55)
    out = np.zeros(n)
    for i, f in enumerate(notes):
        start = i * gap
        ln = n - start
        voice = tone(f, ln, harmonics=((1, 1.0), (4.0, 0.26), (10.0, 0.07)))
        out[start:] += voice * env_perc(ln, decay=0.30) * (0.55 + i * 0.15)
    return out


def sfx_transition():
    """A swoosh. Bandpassed noise whose centre frequency rises and falls,
    which is a page turning rather than a door closing."""
    n = int(RATE * 0.26)
    t = np.arange(n) / n
    base = noise(n, 4)
    # Two filtered copies crossfaded is a cheap sweeping band.
    low = lowpass(base, 700)
    high = highpass(lowpass(base, 4200), 1400)
    curve = np.sin(math.pi * t)
    return (low * (1 - curve) + high * curve) * curve


def sfx_mascot():
    """A friendly two-syllable blip — gibberish, not words, so it means
    the same to every child whatever they speak."""
    n = int(RATE * 0.26)
    half = n // 2
    t = np.arange(n) / RATE
    # A rising pair of vowel-ish tones with vibrato.
    f = np.concatenate([
        np.full(half, 420.0),
        np.full(n - half, 560.0),
    ])
    f = f * (1 + 0.04 * np.sin(2 * math.pi * 11 * t))
    phase = np.cumsum(2 * math.pi * f / RATE)
    voice = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
    gate = np.ones(n)
    # A dip between the syllables makes it two sounds rather than a slide.
    gate[half - 400:half + 400] *= np.linspace(1, 0.15, 800) ** 2
    return voice * gate * env_perc(n, decay=0.5, curve=1.6)


SOUNDS = {
    "tap.wav": sfx_tap,
    "color.wav": sfx_color,
    "draw.wav": sfx_draw,
    "fill.wav": sfx_fill,
    "complete.wav": sfx_complete,
    "transition.wav": sfx_transition,
    "mascot.wav": sfx_mascot,
}

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "sounds",
)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SOUNDS.items():
        write(name, fn())
    total = sum(
        os.path.getsize(os.path.join(OUT, n)) for n in SOUNDS
    )
    print(f"\n{len(SOUNDS)} sounds, {total//1024}KB total")


if __name__ == "__main__":
    main()

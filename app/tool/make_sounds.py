"""Synthesizes the app's sound effects into ``app/assets/sounds/``.

Pure Python (``wave``, ``math``, ``random``): no third-party audio, so there is
nothing to license. Every sound is a few additive sine partials with a soft
attack and an exponential decay, normalized to a fixed peak (no clipping) and
written as 16-bit mono PCM WAV at 22.05 kHz. WAV plays on every platform the
app targets (Android, iOS, macOS, Windows, Linux and browsers), unlike OGG,
which iOS and Safari can't decode.

Run from anywhere::

    python app/tool/make_sounds.py            # writes app/assets/sounds/*.wav
    python app/tool/make_sounds.py --out DIR  # somewhere else

The output is deterministic (the click noise uses a fixed seed), so the
committed files only change when this script does.

Sounds:

* ``correct``  two quick ascending notes a major third apart (E5 -> G#5), bell-like
* ``wrong``    low, soft, descending (E4 -> C4), muted triangle-ish timbre
* ``complete`` a short major arpeggio (C5 E5 G5 C6) that rings out
* ``level_up`` a brighter, faster arpeggio (G5 C6 E6 G6)
* ``bonus``    a quick rising shimmer (C6 D6 G6) for a bonus round start
* ``select``   a very short, quiet, low-passed click (~35 ms) for taps
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050

# Peak level per sound in dBFS: the click is deliberately much quieter.
PEAKS_DB = {
    "correct": -3.0,
    "wrong": -7.0,
    "complete": -3.0,
    "level_up": -3.5,
    "bonus": -5.0,
    "select": -18.0,
}


def note(name: str) -> float:
    """Frequency of a note like 'C5' or 'G#5' (A4 = 440 Hz)."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    letter, rest = name[0], name[1:]
    semis = names[letter]
    if rest.startswith("#"):
        semis += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        semis -= 1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2 ** ((semis + 12 * (octave - 4)) / 12)


def blank(seconds: float) -> list[float]:
    return [0.0] * int(round(seconds * RATE))


def add_tone(
    buf: list[float],
    start: float,
    freq: float,
    *,
    length: float,
    amp: float = 1.0,
    attack: float = 0.006,
    tau: float = 0.12,
    partials: tuple[tuple[float, float], ...] = ((1, 1.0), (2, 0.22), (3, 0.06)),
) -> None:
    """Mixes one note into [buf]: additive partials (ratio, gain), a raised-cosine
    attack of [attack] seconds and an exponential decay with time constant [tau]."""
    i0 = int(round(start * RATE))
    n = int(round(length * RATE))
    for k in range(n):
        i = i0 + k
        if i >= len(buf):
            break
        t = k / RATE
        env = math.exp(-t / tau)
        if t < attack:
            env *= 0.5 - 0.5 * math.cos(math.pi * t / attack)
        s = 0.0
        for ratio, gain in partials:
            f = freq * ratio
            if f < RATE / 2:
                # Higher partials die away faster, like a struck bar.
                s += gain * math.exp(-t * (ratio - 1) * 6) * math.sin(2 * math.pi * f * t)
        buf[i] += amp * env * s


def lowpass(buf: list[float], cutoff: float) -> list[float]:
    """One-pole low-pass filter."""
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for x in buf:
        y += a * (x - y)
        out.append(y)
    return out


def finish(buf: list[float], peak_db: float, fade: float = 0.01) -> list[float]:
    """Fades the tail out, removes DC and normalizes to [peak_db] dBFS."""
    n = len(buf)
    f = min(n, int(fade * RATE))
    for k in range(f):
        buf[n - f + k] *= 1 - (k + 1) / f
    mean = sum(buf) / n
    buf = [x - mean for x in buf]
    peak = max(abs(x) for x in buf) or 1.0
    target = 10 ** (peak_db / 20)
    return [x * target / peak for x in buf]


# ---------------------------------------------------------------- sounds

BELL = ((1, 1.0), (2, 0.22), (3, 0.07), (4.2, 0.03))
SOFT = ((1, 1.0), (3, 0.11), (5, 0.03))  # odd partials: a soft triangle-ish tone


def correct() -> list[float]:
    buf = blank(0.42)
    add_tone(buf, 0.000, note("E5"), length=0.30, amp=0.75, tau=0.09, partials=BELL)
    add_tone(buf, 0.075, note("G#5"), length=0.34, amp=1.0, tau=0.13, partials=BELL)
    return buf


def wrong() -> list[float]:
    buf = blank(0.40)
    add_tone(buf, 0.000, note("E4"), length=0.20, amp=0.9, attack=0.012, tau=0.09, partials=SOFT)
    add_tone(buf, 0.110, note("C4"), length=0.29, amp=1.0, attack=0.012, tau=0.12, partials=SOFT)
    return lowpass(buf, 1800)


def complete() -> list[float]:
    buf = blank(1.0)
    for i, n in enumerate(["C5", "E5", "G5"]):
        add_tone(buf, i * 0.09, note(n), length=0.45, amp=0.7, tau=0.14, partials=BELL)
    add_tone(buf, 0.27, note("C6"), length=0.73, amp=1.0, tau=0.26, partials=BELL)
    add_tone(buf, 0.27, note("G5"), length=0.73, amp=0.35, tau=0.22, partials=BELL)
    return buf


def level_up() -> list[float]:
    buf = blank(0.85)
    for i, n in enumerate(["G5", "C6", "E6"]):
        add_tone(buf, i * 0.065, note(n), length=0.35, amp=0.65, tau=0.10, partials=BELL)
    add_tone(buf, 0.195, note("G6"), length=0.65, amp=1.0, tau=0.22, partials=BELL)
    add_tone(buf, 0.195, note("C6"), length=0.65, amp=0.4, tau=0.20, partials=BELL)
    return buf


def bonus() -> list[float]:
    buf = blank(0.55)
    for i, n in enumerate(["C6", "D6", "G6"]):
        add_tone(buf, i * 0.055, note(n), length=0.40, amp=0.8 + 0.1 * i, tau=0.10, partials=BELL)
    return buf


def select() -> list[float]:
    buf = blank(0.035)
    rnd = random.Random(7)
    noise = [rnd.uniform(-1, 1) * math.exp(-(k / RATE) / 0.004) for k in range(len(buf))]
    noise = lowpass(lowpass(noise, 2500), 2500)
    add_tone(buf, 0.0, 950.0, length=0.035, amp=0.6, attack=0.0015, tau=0.007, partials=((1, 1.0),))
    return [a + 2.5 * b for a, b in zip(buf, noise)]


SOUNDS = {
    "correct": correct,
    "wrong": wrong,
    "complete": complete,
    "level_up": level_up,
    "bonus": bonus,
    "select": select,
}


def write_wav(path: Path, samples: list[float]) -> None:
    frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(round(s * 32767))))) for s in samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def main() -> None:
    default_out = Path(__file__).resolve().parent.parent / "assets" / "sounds"
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--out", type=Path, default=default_out)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        samples = finish(make(), PEAKS_DB[name])
        path = args.out / f"{name}.wav"
        write_wav(path, samples)
        peak = max(abs(s) for s in samples)
        print(f"{path.name:14} {len(samples) / RATE * 1000:5.0f} ms  peak {20 * math.log10(peak):6.1f} dBFS  "
              f"{path.stat().st_size / 1024:5.1f} KB")


if __name__ == "__main__":
    main()

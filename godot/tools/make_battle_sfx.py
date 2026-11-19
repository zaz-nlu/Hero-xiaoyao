"""Synthesises the tactics-battle feedback sounds (clash, block, weakness hit, break).

Run from the repo root:  py -3 godot/tools/make_battle_sfx.py
Reuses the helpers and output folder of make_music.py; every run renders identical files.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_music import SR, fir_bandpass, fir_highpass, fir_lowpass, tt, write_wav  # noqa: E402


def norm(x, peak=0.8):
    x = x - np.mean(x)
    return x * peak / (np.max(np.abs(x)) + 1e-9)


def click(n, ms=2.5, level=1.0, seed=1):
    """A very short broadband tick: the 'contact' part of a metal strike."""
    rng = np.random.default_rng(seed)
    t = tt(n)
    return fir_highpass(rng.standard_normal(n), 2500) * np.exp(-t * (1000.0 / ms)) * level


def steel(n, base, decay, partials=None, level=1.0):
    """Inharmonic bar-like partials, the ring of struck steel."""
    t = tt(n)
    parts = partials or [(1.0, 1.0), (2.32, 0.75), (4.25, 0.55), (6.63, 0.38), (9.38, 0.25)]
    y = np.zeros(n)
    for k, (ratio, amp) in enumerate(parts):
        y += amp * np.sin(2 * np.pi * base * ratio * t + 0.7 * k) * np.exp(-t * decay * (1.0 + 0.55 * k))
    return y * level


def make_parry():
    """Perfect parry: two blades meeting. Bright, short, with a quick 'shing' sweep."""
    n = int(0.62 * SR)
    t = tt(n)
    y = click(n, 3.0, 1.0, seed=11) + steel(n, 1720, 7.0, level=0.95)
    sweep = fir_highpass(np.random.default_rng(12).standard_normal(n), 5200) * np.exp(-t * 16)
    y += sweep * 0.28 * np.clip(t / 0.01, 0, 1)
    return norm(y, 0.85)


def make_parry_soft():
    """Ordinary counter: the same clash, lower and shorter so a perfect one stands out."""
    n = int(0.4 * SR)
    y = click(n, 3.0, 0.8, seed=21) + steel(n, 1180, 9.5, level=0.9)
    return norm(y, 0.7)


def make_block():
    """Basic block: a dull clang, little ring."""
    n = int(0.28 * SR)
    t = tt(n)
    y = click(n, 4.0, 0.5, seed=31) + steel(n, 520, 20.0, level=0.9)
    y += np.sin(2 * np.pi * 120 * t) * np.exp(-t * 28) * 0.6
    return norm(y, 0.65)


def make_weak():
    """Weakness struck: a crisp glassy 'ding' with a rising two-note sparkle."""
    n = int(0.7 * SR)
    t = tt(n)
    y = click(n, 2.0, 0.7, seed=41)
    for start, f, amp in [(0.0, 2350, 1.0), (0.075, 3520, 0.9)]:
        o = int(start * SR)
        m = n - o
        tm = tt(m)
        note = (np.sin(2 * np.pi * f * tm) + 0.4 * np.sin(2 * np.pi * f * 2.76 * tm)) * np.exp(-tm * 11)
        y[o:] += note * amp
    y += fir_highpass(np.random.default_rng(42).standard_normal(n), 6500) * np.exp(-t * 22) * 0.2
    return norm(y, 0.8)


def make_break():
    """Toughness shattered: a crack, falling glass and a low thump."""
    n = int(1.0 * SR)
    t = tt(n)
    rng = np.random.default_rng(51)
    y = click(n, 5.0, 1.0, seed=52)
    y += np.sin(2 * np.pi * 70 * (1 + 0.9 * np.exp(-t * 24)) * t) * np.exp(-t * 11) * 0.9
    glass = np.zeros(n)
    for _ in range(26):
        o = int(rng.uniform(0.0, 0.42) * SR)
        f = rng.uniform(2200, 7200)
        m = n - o
        tm = tt(m)
        glass[o:] += np.sin(2 * np.pi * f * tm) * np.exp(-tm * rng.uniform(40, 90)) * rng.uniform(0.2, 0.55)
    y += glass * 0.55
    y += fir_bandpass(rng.standard_normal(n), 1500, 6000) * np.exp(-t * 9) * 0.35
    return norm(y, 0.85)


SOUNDS = {
    "sfx_parry": make_parry,
    "sfx_parry_soft": make_parry_soft,
    "sfx_block": make_block,
    "sfx_weak": make_weak,
    "sfx_break": make_break,
}


def main():
    wanted = sys.argv[1:]
    for name, fn in SOUNDS.items():
        if wanted and name not in wanted:
            continue
        write_wav(name, fn())


if __name__ == "__main__":
    main()

"""Procedural wuxia music + sfx renderer (no samples, pure numpy synthesis).

Usage (from repo root):   python godot/tools/make_music.py [name ...]
Writes mono 16-bit 22050 Hz WAV files to godot/assets/audio/.

Instruments are additive/subtractive imitations of: guzheng/pipa (plucked), dizi (flute), erhu
(bowed), taiko / hand drum / wood block / cymbal / gong. Tracks are built on pentatonic scales
from seeded RNGs, so every run renders the same music. Loops are seamless: notes that run past the
end wrap around, and the reverb is a circular convolution.
"""
import os
import sys
import wave

import numpy as np

SR = 22050
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio"))

MAJOR_PENT = [0, 2, 4, 7, 9]
MINOR_PENT = [0, 3, 5, 7, 10]
HIRAJOSHI = [0, 2, 3, 7, 8]
TENSE_PENT = [0, 1, 5, 7, 8]


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def tt(n):
    return np.arange(n) / SR


def note_midi(root, steps, idx):
    return root + 12 * (idx // len(steps)) + steps[idx % len(steps)]


# ------------------------------------------------------------------ filters
def fir_lowpass(x, cutoff, taps=81):
    fc = cutoff / SR
    n = np.arange(taps) - (taps - 1) / 2
    h = np.sinc(2 * fc * n) * np.hamming(taps)
    h /= h.sum()
    return np.convolve(x, h, mode="same")


def fir_highpass(x, cutoff, taps=81):
    return x - fir_lowpass(x, cutoff, taps)


def fir_bandpass(x, lo, hi, taps=101):
    return fir_lowpass(fir_highpass(x, lo, taps), hi, taps)


# ------------------------------------------------------------------ instruments
def pluck(freq, dur, bright=0.62, decay=2.2, seed=0):
    """Guzheng / pipa style plucked string: decaying inharmonic partials plus a tiny noise click."""
    n = max(8, int(dur * SR))
    t = tt(n)
    out = np.zeros(n)
    kmax = int(min(14, 9000 // max(freq, 1)))
    for k in range(1, kmax + 1):
        f = freq * k * (1 + 0.00035 * k * k)
        amp = (bright ** (k - 1)) / (k ** 0.9)
        out += amp * np.sin(2 * np.pi * f * t) * np.exp(-t * decay * (1 + 0.55 * (k - 1)))
    rng = np.random.default_rng(seed)
    click = fir_lowpass(rng.standard_normal(n), 5000) * np.exp(-t * 90) * 0.35
    out += click
    atk = np.minimum(1.0, t / 0.002)
    return out * atk * 0.55


def flute(freq, dur, vib=0.0045, vib_rate=5.3, breath=0.10, attack=0.07, release=0.14, seed=0):
    n = max(8, int(dur * SR))
    t = tt(n)
    vib_env = np.minimum(1.0, t / 0.35)
    f = freq * (1 + vib * vib_env * np.sin(2 * np.pi * vib_rate * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = np.sin(phase) + 0.32 * np.sin(2 * phase) + 0.1 * np.sin(3 * phase)
    rng = np.random.default_rng(seed)
    noise = fir_bandpass(rng.standard_normal(n), freq * 1.5, min(9000, freq * 6)) * breath * 3.0
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, (dur - t)) / release)
    env *= 0.92 + 0.08 * np.sin(2 * np.pi * 4.1 * t)
    return (sig * 0.5 + noise) * env * 0.6


def erhu(freq, dur, slide_from=0.965, attack=0.09, release=0.18, seed=0):
    n = max(8, int(dur * SR))
    t = tt(n)
    glide = slide_from + (1 - slide_from) * np.minimum(1.0, t / 0.07)
    vib_env = np.clip((t - 0.18) / 0.3, 0, 1)
    f = freq * glide * (1 + 0.007 * vib_env * np.sin(2 * np.pi * 5.6 * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = np.zeros(n)
    for k in range(1, 13):
        sig += np.sin(k * phase) / (k ** 0.95)
    rng = np.random.default_rng(seed)
    bow = fir_bandpass(rng.standard_normal(n), 1200, 3500) * 0.05
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, (dur - t)) / release)
    sig = fir_lowpass(sig, 3200)
    return (sig * 0.38 + bow) * env * 0.7


def taiko(dur=0.7, pitch=70.0, power=1.0, seed=0):
    n = int(dur * SR)
    t = tt(n)
    freq = pitch * (1 + 1.6 * np.exp(-t * 28))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t * 5.5)
    rng = np.random.default_rng(seed)
    skin = fir_bandpass(rng.standard_normal(n), 200, 1800) * np.exp(-t * 38) * 0.5
    return (body + skin) * power * 0.95


def hand_drum(dur=0.35, pitch=170.0, seed=0):
    n = int(dur * SR)
    t = tt(n)
    freq = pitch * (1 + 0.8 * np.exp(-t * 45))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    rng = np.random.default_rng(seed)
    return (np.sin(phase) * np.exp(-t * 16) + fir_bandpass(rng.standard_normal(n), 400, 3000) * np.exp(-t * 60) * 0.35) * 0.8


def woodblock(dur=0.12, pitch=1100.0):
    n = int(dur * SR)
    t = tt(n)
    return (np.sin(2 * np.pi * pitch * t) + 0.5 * np.sin(2 * np.pi * pitch * 1.52 * t)) * np.exp(-t * 55) * 0.5


def cymbal(dur=0.8, seed=0, bright=1.0):
    n = int(dur * SR)
    t = tt(n)
    rng = np.random.default_rng(seed)
    return fir_highpass(rng.standard_normal(n), 3500 * bright) * np.exp(-t * 6.5) * 0.3


def gong(freq=110.0, dur=3.0):
    n = int(dur * SR)
    t = tt(n)
    out = np.zeros(n)
    for k, a in [(1.0, 1.0), (1.51, 0.6), (2.07, 0.5), (2.9, 0.35), (3.7, 0.25), (4.6, 0.18)]:
        out += a * np.sin(2 * np.pi * freq * k * t + 0.3 * np.sin(2 * np.pi * 0.7 * t)) * np.exp(-t * (0.9 + 0.5 * k))
    return out * np.minimum(1.0, t / 0.01) * 0.45


def pad(freq, dur, seed=0):
    """Soft sustained pad (detuned partials with slow swell) for drones."""
    n = int(dur * SR)
    t = tt(n)
    out = np.zeros(n)
    for k, a in [(1, 1.0), (2, 0.4), (3, 0.2)]:
        for d in (-0.0035, 0.0, 0.0035):
            out += a * np.sin(2 * np.pi * freq * k * (1 + d) * t + seed)
    swell = np.minimum(1.0, t / 1.5) * np.minimum(1.0, (dur - t) / 1.5)
    return out * swell * 0.12


# ------------------------------------------------------------------ track helper
class Track:
    def __init__(self, bars, bpm, beats=4):
        self.bpm = bpm
        self.beats = beats
        self.bars = bars
        self.spb = 60.0 / bpm
        self.n = int(round(bars * beats * self.spb * SR))
        self.buf = np.zeros(self.n)

    def at(self, bar, beat):
        return (bar * self.beats + beat) * self.spb

    def place(self, snd, t_sec, gain=1.0):
        start = int(round(t_sec * SR)) % self.n
        end = start + len(snd)
        if end <= self.n:
            self.buf[start:end] += snd * gain
        else:
            first = self.n - start
            self.buf[start:] += snd[:first] * gain
            rest = snd[first:]
            while len(rest) > 0:
                m = min(len(rest), self.n)
                self.buf[:m] += rest[:m] * gain
                rest = rest[m:]

    def reverb(self, decay=1.6, wet=0.25, seed=1, damp=4500):
        rng = np.random.default_rng(seed)
        m = int(decay * 1.4 * SR)
        t = tt(m)
        ir = rng.standard_normal(m) * np.exp(-t * (6.9 / decay))
        ir = fir_lowpass(ir, damp)
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        pad_len = self.n
        spec = np.fft.rfft(self.buf, n=pad_len) * np.fft.rfft(ir, n=pad_len)
        wetsig = np.fft.irfft(spec, n=pad_len)
        self.buf = self.buf * (1 - wet * 0.5) + wetsig * wet * 1.6

    def finish(self, target_rms=0.11, peak=0.92, soften=True):
        x = self.buf - np.mean(self.buf)
        if soften:
            # circular low-pass (wrap the edges so loops stay seamless) + a gentle high-shelf cut
            k = 120
            wrapped = np.concatenate([x[-k:], x, x[:k]])
            x = fir_lowpass(wrapped, 4800, taps=101)[k:-k]
        rms = np.sqrt(np.mean(x ** 2)) + 1e-9
        x *= target_rms / rms
        x = np.tanh(x * 1.15) / np.tanh(1.15)
        m = np.max(np.abs(x)) + 1e-9
        if m > peak:
            x *= peak / m
        return x


def write_wav(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = np.clip(x, -1, 1)
    pcm = (data * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote %s  %.1fs  %.2f MB  peak %.2f  rms %.3f" % (name, len(x) / SR, os.path.getsize(path) / 1e6, float(np.max(np.abs(x))), float(np.sqrt(np.mean(x ** 2)))))


# ------------------------------------------------------------------ composition helpers
RHYTHMS = [
    [1, 1, 1, 1], [2, 1, 1], [1, 1, 2], [1.5, 0.5, 1, 1], [2, 2], [1, 0.5, 0.5, 1, 1],
    [0.5, 0.5, 1, 2], [3, 1], [1, 1, 1, 0.5, 0.5], [1.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 2],
]


def melody_bars(rng, chords, lo, hi, rhythms=None, rest_prob=0.12, start=None, end_on=None):
    """chords: list of chord root scale-indices (one per bar). Returns [[(beat, idx, dur), ...], ...]."""
    rhythms = rhythms or RHYTHMS
    bars = []
    prev = start if start is not None else chords[0] + 5
    for b, c in enumerate(chords):
        pattern = rhythms[rng.integers(len(rhythms))]
        events = []
        beat = 0.0
        tones = [c, c + 2, c + 4, c + 5, c - 3]
        for j, d in enumerate(pattern):
            if rng.random() < rest_prob and j > 0:
                beat += d
                continue
            if j == 0:
                cand = [x for x in tones if lo <= x <= hi]
                nxt = min(cand, key=lambda x: abs(x - prev) + rng.random()) if cand else prev
            else:
                nxt = prev + int(rng.choice([-2, -1, -1, 0, 1, 1, 2]))
            nxt = int(min(hi, max(lo, nxt)))
            events.append((beat, nxt, d))
            prev = nxt
            beat += d
        bars.append(events)
    if end_on is not None and bars and bars[-1]:
        b, _, d = bars[-1][-1]
        bars[-1][-1] = (b, end_on, d)
    return bars


def arpeggio(tr, bar, chord_idx, root, steps, shape, gain, bright=0.7, decay=2.4, step_beats=0.5, lift=0, seed=0):
    for j, off in enumerate(shape):
        idx = chord_idx + off + lift
        m = note_midi(root, steps, idx)
        tr.place(pluck(hz(m), 1.8, bright, decay, seed + j), tr.at(bar, j * step_beats), gain)


def gliss(tr, bar, beat, root, steps, start_idx, count, gain, step=0.045, direction=1, seed=0):
    t0 = tr.at(bar, beat)
    for j in range(count):
        m = note_midi(root, steps, start_idx + direction * j)
        tr.place(pluck(hz(m), 1.4, 0.7, 2.8, seed + j), t0 + j * step, gain * (0.6 + 0.4 * j / count))


# ------------------------------------------------------------------ tracks
def make_town():
    root, steps = 62, MAJOR_PENT
    tr = Track(16, 80)
    rng = np.random.default_rng(11)
    prog = [0, 0, 4, 4, 3, 3, 2, 1, 0, 0, 4, 4, 3, 1, 0, 0]
    shapes = [[0, 2, 4, 7, 4, 2, 4, 2], [0, 2, 4, 2, 7, 4, 2, 0], [0, 4, 7, 4, 2, 4, 7, 9]]
    for b, c in enumerate(prog):
        arpeggio(tr, b, c + 5, root, steps, shapes[b % 3], 0.34, step_beats=0.5, seed=b * 7)
        tr.place(pluck(hz(note_midi(root, steps, c)), 2.2, 0.5, 1.8, b), tr.at(b, 0), 0.5)
        tr.place(pluck(hz(note_midi(root, steps, c + 4)), 1.5, 0.5, 2.0, b + 1), tr.at(b, 2), 0.28)
        tr.place(woodblock(0.1, 980), tr.at(b, 1), 0.13)
        tr.place(woodblock(0.1, 760), tr.at(b, 3), 0.1)
    phraseA = melody_bars(rng, prog[0:4], 7, 12, rest_prob=0.1, start=9)
    phraseB = melody_bars(rng, prog[4:8], 6, 12, rest_prob=0.12, start=8, end_on=5)
    sequence = [phraseA, phraseA, phraseB, phraseA]
    for p, phrase in enumerate(sequence):
        for q, events in enumerate(phrase):
            bar = p * 4 + q
            for beat, idx, d in events:
                m = note_midi(root, steps, idx + 5)
                tr.place(flute(hz(m), d * tr.spb * 0.95, seed=bar * 11 + int(beat * 4)), tr.at(bar, beat), 0.55)
    for b in range(8, 16, 2):
        c = prog[b]
        tr.place(erhu(hz(note_midi(root, steps, c + 5)), 7.0 * tr.spb, seed=b), tr.at(b, 0), 0.26)
    for b in (3, 7, 11, 15):
        gliss(tr, b, 3.0, root, steps, 5 + prog[b], 6, 0.3, seed=b)
    tr.reverb(2.0, 0.3, seed=3)
    return tr.finish(0.1)


def make_tavern():
    root, steps = 57, MINOR_PENT
    tr = Track(16, 112)
    rng = np.random.default_rng(23)
    prog = [0, 0, 2, 2, 3, 3, 1, 0, 0, 0, 2, 3, 4, 3, 1, 0]
    for b, c in enumerate(prog):
        for j in range(8):
            idx = c + 5 + [0, 2, 0, 4, 0, 2, 4, 2][j]
            m = note_midi(root, steps, idx)
            tr.place(pluck(hz(m), 0.55, 0.85, 4.5, b * 8 + j), tr.at(b, j * 0.5), 0.32 if j % 2 == 0 else 0.22)
        tr.place(pluck(hz(note_midi(root, steps, c)), 0.9, 0.5, 3.0, b), tr.at(b, 0), 0.5)
        tr.place(pluck(hz(note_midi(root, steps, c)), 0.7, 0.5, 3.0, b + 9), tr.at(b, 2), 0.4)
        tr.place(hand_drum(0.35, 150, b), tr.at(b, 0), 0.5)
        tr.place(hand_drum(0.3, 190, b + 1), tr.at(b, 2), 0.4)
        for h in (1, 3):
            tr.place(woodblock(0.1, 1250), tr.at(b, h), 0.3)
        for h in (0.5, 1.5, 2.5, 3.5):
            tr.place(woodblock(0.06, 1700), tr.at(b, h), 0.1)
    phraseA = melody_bars(rng, prog[0:4], 6, 12, rest_prob=0.08, start=8)
    phraseB = melody_bars(rng, prog[4:8], 5, 11, rest_prob=0.1, start=7, end_on=5)
    sequence = [phraseA, phraseA, phraseB, phraseA]
    for p, phrase in enumerate(sequence):
        for q, events in enumerate(phrase):
            bar = p * 4 + q
            for beat, idx, d in events:
                m = note_midi(root, steps, idx + 5)
                if rng.random() < 0.25:
                    g = note_midi(root, steps, idx + 6)
                    tr.place(erhu(hz(g), 0.12 * tr.spb, slide_from=0.99, attack=0.01, release=0.04), tr.at(bar, beat) - 0.08 * tr.spb, 0.22)
                tr.place(erhu(hz(m), d * tr.spb * 0.97, seed=bar * 5 + int(beat * 4)), tr.at(bar, beat), 0.4)
    tr.reverb(1.2, 0.2, seed=5)
    return tr.finish(0.105)


def make_tavern_brawl():
    root, steps = 50, MINOR_PENT
    tr = Track(16, 138)
    rng = np.random.default_rng(37)
    prog = [0, 0, 0, 3, 0, 0, 2, 3, 0, 0, 0, 3, 2, 2, 3, 0]
    tr.place(gong(73.0, 3.2), 0.0, 0.7)
    tr.place(gong(73.0, 3.2), tr.at(8, 0), 0.7)
    for b, c in enumerate(prog):
        tr.place(taiko(0.8, 62, 1.0, b), tr.at(b, 0), 0.95)
        tr.place(taiko(0.6, 74, 0.7, b + 1), tr.at(b, 1.5), 0.6)
        tr.place(taiko(0.8, 66, 0.9, b + 2), tr.at(b, 2), 0.85)
        tr.place(taiko(0.5, 80, 0.6, b + 3), tr.at(b, 3.5), 0.55)
        for j in range(16):
            idx = c + 5 + [0, 4, 2, 4, 0, 4, 2, 4, 0, 2, 4, 7, 4, 2, 4, 2][j]
            m = note_midi(root, steps, idx)
            tr.place(pluck(hz(m), 0.3, 0.9, 7.0, b * 16 + j), tr.at(b, j * 0.25), 0.2 if j % 4 else 0.3)
        tr.place(cymbal(0.5, b, 1.0), tr.at(b, 1), 0.28)
        tr.place(cymbal(0.5, b + 5, 1.0), tr.at(b, 3), 0.28)
        if b % 4 == 3:
            for j in range(8):
                tr.place(taiko(0.3, 90 - j * 3, 0.5, j), tr.at(b, 2 + j * 0.25), 0.4 + j * 0.05)
        tr.place(pad(hz(note_midi(root, steps, c - 5)), 4 * tr.spb * 1.05, b), tr.at(b, 0), 0.9)
    for p in range(4):
        events = melody_bars(rng, prog[p * 4:(p + 1) * 4], 6, 11, rhythms=[[2, 2], [1, 1, 2], [3, 1], [1.5, 0.5, 2]], rest_prob=0.0, start=8)
        for q, evs in enumerate(events):
            bar = p * 4 + q
            for beat, idx, d in evs:
                m = note_midi(root, steps, idx + 5)
                tr.place(erhu(hz(m), d * tr.spb * 0.98, slide_from=0.94, seed=bar), tr.at(bar, beat), 0.38)
    tr.reverb(1.0, 0.18, seed=9)
    return tr.finish(0.12)


def make_forest():
    root, steps = 62, MAJOR_PENT
    tr = Track(12, 56)
    rng = np.random.default_rng(41)
    for b in range(12):
        tr.place(pad(hz(50), 4 * tr.spb * 1.1, b), tr.at(b, 0), 1.0)
        tr.place(pad(hz(57), 4 * tr.spb * 1.1, b + 2), tr.at(b, 0), 0.7)
    t = 0.0
    total = tr.n / SR
    while t < total - 3:
        idx = int(rng.integers(3, 12))
        m = note_midi(root, steps, idx)
        tr.place(pluck(hz(m), 3.2, 0.6, 1.1, int(t * 10)), t, 0.4 + 0.3 * rng.random())
        t += float(rng.choice([1.1, 1.8, 2.6, 3.5]))
    for p, (b, idxs) in enumerate([(1, [9, 8, 7, 9]), (5, [8, 7, 5, 7, 8]), (9, [9, 11, 9, 8, 7])]):
        t0 = tr.at(b, 0)
        for j, idx in enumerate(idxs):
            m = note_midi(root, steps, idx)
            d = 1.2 + 0.8 * (j % 2)
            tr.place(flute(hz(m), d * tr.spb * 1.4, breath=0.14, attack=0.12, release=0.3, seed=p * 9 + j), t0 + j * 2.4 * tr.spb, 0.5)
    wind = fir_lowpass(np.random.default_rng(5).standard_normal(tr.n), 700)
    mod = 0.5 + 0.5 * np.sin(2 * np.pi * (np.arange(tr.n) / SR) / (total / 3.0))
    tr.buf += wind * mod * 0.05
    tr.reverb(3.2, 0.45, seed=7, damp=3500)
    return tr.finish(0.07)


def bird_whistle(f0=3300, f1=2400, dur=0.26, seed=0):
    n = int(dur * SR)
    t = tt(n)
    f = f0 + (f1 - f0) * (t / dur) ** 0.8
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7
    return (np.sin(ph) + 0.18 * np.sin(2 * ph)) * env * 0.5


def bird_trill(f=4400, count=7, gap=0.055, seed=0):
    out = np.zeros(int((count * gap + 0.1) * SR))
    for j in range(count):
        n = int(0.035 * SR)
        t = tt(n)
        s = np.sin(2 * np.pi * (f + 250 * np.sin(j)) * t) * np.sin(np.pi * np.clip(t / 0.035, 0, 1))
        i0 = int(j * gap * SR)
        out[i0:i0 + n] += s * 0.45
    return out


def bird_chirp(f0=2800, f1=3700, dur=0.11):
    n = int(dur * SR)
    t = tt(n)
    f = f0 + (f1 - f0) * t / dur
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.sin(np.pi * np.clip(t / dur, 0, 1)) * 0.5


def bird_cuckoo(f=760, dur=0.28):
    n = int(dur * SR)
    t = tt(n)
    out = np.sin(2 * np.pi * f * (1 - 0.12 * t / dur) * t) * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.5
    return out * 0.55


def make_forest_birds():
    tr = Track(10, 60)
    rng = np.random.default_rng(53)
    total = tr.n / SR
    wind = fir_lowpass(np.random.default_rng(7).standard_normal(tr.n), 900)
    tt_ = np.arange(tr.n) / SR
    mod = 0.55 + 0.45 * np.sin(2 * np.pi * tt_ / (total / 2.0) + 1.0)
    tr.buf += wind * mod * 0.09
    t = 0.5
    while t < total - 2.0:
        kind = rng.integers(5)
        gain = 0.18 + 0.3 * rng.random()
        if kind == 0:
            tr.place(bird_whistle(3300 + rng.integers(-300, 300), 2400, 0.26), t, gain)
            tr.place(bird_whistle(3000 + rng.integers(-200, 300), 2200, 0.3), t + 0.34, gain * 0.9)
        elif kind == 1:
            tr.place(bird_trill(4300 + rng.integers(-300, 400), int(rng.integers(5, 10))), t, gain * 0.8)
        elif kind == 2:
            for j in range(int(rng.integers(2, 5))):
                tr.place(bird_chirp(2800 + rng.integers(-200, 300), 3700), t + j * 0.16, gain * 0.7)
        elif kind == 3 and rng.random() < 0.5:
            tr.place(bird_cuckoo(760), t, gain * 0.9)
            tr.place(bird_cuckoo(640), t + 0.42, gain * 0.9)
        else:
            tr.place(bird_whistle(3600, 3000, 0.18), t, gain * 0.7)
        t += float(rng.uniform(0.9, 3.4))
    tr.reverb(1.8, 0.3, seed=11, damp=4000)
    return tr.finish(0.06, peak=0.8)


def make_battle():
    root, steps = 57, MINOR_PENT
    tr = Track(16, 150)
    rng = np.random.default_rng(61)
    prog = [0, 0, 3, 3, 2, 2, 3, 4, 0, 0, 3, 3, 2, 3, 4, 0]
    for b, c in enumerate(prog):
        tr.place(taiko(0.7, 68, 1.0, b), tr.at(b, 0), 0.95)
        tr.place(taiko(0.5, 78, 0.6, b + 1), tr.at(b, 1.5), 0.55)
        tr.place(taiko(0.7, 70, 0.9, b + 2), tr.at(b, 2), 0.8)
        tr.place(taiko(0.4, 84, 0.5, b + 3), tr.at(b, 3), 0.5)
        tr.place(taiko(0.4, 84, 0.5, b + 4), tr.at(b, 3.5), 0.5)
        for h in (1, 3):
            tr.place(cymbal(0.4, b + h, 1.1), tr.at(b, h), 0.2)
        shape = [0, 2, 4, 2, 0, 2, 4, 7, 4, 2, 4, 2, 0, 4, 2, 0]
        for j in range(16):
            m = note_midi(root, steps, c + 5 + shape[j])
            tr.place(pluck(hz(m), 0.28, 0.9, 8.0, b * 16 + j), tr.at(b, j * 0.25), 0.18 if j % 4 else 0.28)
        tr.place(pluck(hz(note_midi(root, steps, c)), 0.5, 0.5, 4.0, b), tr.at(b, 0), 0.5)
        if b % 4 == 3:
            for j in range(8):
                tr.place(taiko(0.25, 95 - j * 3, 0.5, j), tr.at(b, 3 + j * 0.125), 0.35 + j * 0.06)
    for p in range(4):
        events = melody_bars(rng, prog[p * 4:(p + 1) * 4], 6, 12, rhythms=[[1, 1, 1, 1], [1.5, 0.5, 1, 1], [1, 0.5, 0.5, 2], [2, 1, 1]], rest_prob=0.05, start=9)
        for q, evs in enumerate(events):
            bar = p * 4 + q
            for beat, idx, d in evs:
                m = note_midi(root, steps, idx + 5)
                tr.place(flute(hz(m), d * tr.spb * 0.9, vib=0.003, breath=0.16, attack=0.03, release=0.06, seed=bar * 5 + int(beat * 4)), tr.at(bar, beat), 0.5)
    tr.reverb(0.9, 0.16, seed=13)
    return tr.finish(0.12)


def make_battle_boss():
    root, steps = 50, TENSE_PENT
    tr = Track(16, 120)
    rng = np.random.default_rng(71)
    prog = [0, 0, 1, 0, 0, 0, 3, 1, 0, 0, 1, 0, 3, 3, 1, 0]
    for b in range(0, 16, 4):
        tr.place(gong(65.0, 3.5), tr.at(b, 0), 0.8)
    for b, c in enumerate(prog):
        tr.place(taiko(1.0, 55, 1.1, b), tr.at(b, 0), 1.0)
        tr.place(taiko(0.8, 62, 0.8, b + 1), tr.at(b, 2), 0.85)
        tr.place(taiko(0.5, 70, 0.55, b + 2), tr.at(b, 3), 0.5)
        tr.place(taiko(0.4, 80, 0.5, b + 3), tr.at(b, 3.5), 0.45)
        tr.place(hand_drum(0.3, 120, b), tr.at(b, 1), 0.4)
        for j in range(8):
            m = note_midi(root, steps, c + 5 + [0, 3, 0, 2, 0, 3, 4, 2][j])
            tr.place(pluck(hz(m), 0.6, 0.85, 5.0, b * 8 + j), tr.at(b, j * 0.5), 0.24 if j % 2 == 0 else 0.15)
        tr.place(pad(hz(note_midi(root, steps, c - 5)), 4 * tr.spb * 1.05, b), tr.at(b, 0), 1.1)
        tr.place(pad(hz(note_midi(root, steps, c)), 4 * tr.spb * 1.05, b + 3), tr.at(b, 0), 0.7)
        if b % 4 == 3:
            tr.place(cymbal(1.6, b, 0.9), tr.at(b, 3.5), 0.3)
    for p in range(4):
        events = melody_bars(rng, prog[p * 4:(p + 1) * 4], 6, 11, rhythms=[[4], [2, 2], [3, 1], [2, 1, 1]], rest_prob=0.0, start=8)
        for q, evs in enumerate(events):
            bar = p * 4 + q
            for beat, idx, d in evs:
                m = note_midi(root, steps, idx + 5)
                tr.place(erhu(hz(m), d * tr.spb * 0.99, slide_from=0.93, attack=0.12, seed=bar), tr.at(bar, beat), 0.42)
    tr.reverb(1.5, 0.22, seed=17)
    return tr.finish(0.125)


def make_title():
    root, steps = 57, MINOR_PENT
    tr = Track(16, 66)
    rng = np.random.default_rng(83)
    prog = [0, 0, 3, 3, 2, 2, 1, 0, 0, 0, 3, 3, 4, 3, 1, 0]
    tr.place(gong(88.0, 4.5), 0.0, 0.8)
    tr.place(gong(88.0, 4.5), tr.at(8, 0), 0.7)
    for b, c in enumerate(prog):
        tr.place(pad(hz(note_midi(root, steps, c - 5)), 4 * tr.spb * 1.1, b), tr.at(b, 0), 1.0)
        tr.place(pad(hz(note_midi(root, steps, c)), 4 * tr.spb * 1.1, b + 4), tr.at(b, 0), 0.6)
        for j in range(4):
            idx = c + 5 + [0, 2, 4, 2][j]
            tr.place(pluck(hz(note_midi(root, steps, idx)), 2.6, 0.62, 1.6, b * 4 + j), tr.at(b, j), 0.36)
        if b >= 8:
            tr.place(taiko(1.0, 58, 0.8, b), tr.at(b, 0), 0.55)
            tr.place(taiko(0.8, 66, 0.5, b + 1), tr.at(b, 2), 0.4)
    for p in range(4):
        events = melody_bars(rng, prog[p * 4:(p + 1) * 4], 6, 11, rhythms=[[4], [2, 2], [3, 1], [2, 1, 1]], rest_prob=0.0, start=8)
        for q, evs in enumerate(events):
            bar = p * 4 + q
            for beat, idx, d in evs:
                m = note_midi(root, steps, idx + 5)
                tr.place(erhu(hz(m), d * tr.spb * 0.99, slide_from=0.95, attack=0.14, release=0.3, seed=bar), tr.at(bar, beat), 0.4)
                if p >= 2:
                    tr.place(flute(hz(m + 12), d * tr.spb * 0.95, breath=0.12, attack=0.1, release=0.3, seed=bar + 50), tr.at(bar, beat), 0.28)
    for b in (3, 7, 11, 15):
        gliss(tr, b, 3.0, root, steps, 5 + prog[b], 7, 0.3, step=0.06, seed=b)
    tr.reverb(2.8, 0.38, seed=29, damp=4000)
    return tr.finish(0.11)


def stinger(notes, instrument, total, gap, **kw):
    tr = Track(1, 60)
    tr.n = int(total * SR)
    tr.buf = np.zeros(tr.n)
    for i, (m, d) in enumerate(notes):
        tr.place(instrument(hz(m), d, **kw), i * gap, 0.6)
    return tr


def make_victory():
    tr = Track(1, 60)
    tr.n = int(5.5 * SR)
    tr.buf = np.zeros(tr.n)
    run = [62, 66, 69, 74, 78, 81, 86]
    for i, m in enumerate(run):
        tr.place(pluck(hz(m), 2.2, 0.75, 1.8, i), i * 0.11, 0.5)
    for m, g in [(62, 0.5), (69, 0.4), (74, 0.4), (78, 0.35)]:
        tr.place(flute(hz(m + 12) if m < 70 else hz(m), 3.0, breath=0.1, attack=0.1, release=0.6, seed=m), 0.9, g)
    tr.place(taiko(1.2, 60, 0.9), 0.9, 0.7)
    tr.reverb(2.2, 0.35, seed=19)
    x = tr.finish(0.12)
    fade = np.minimum(1.0, np.linspace(1, 0, len(x)) * 6)
    return x * fade


def make_defeat():
    tr = Track(1, 60)
    tr.n = int(6.0 * SR)
    tr.buf = np.zeros(tr.n)
    for i, m in enumerate([69, 67, 64, 62, 57]):
        tr.place(erhu(hz(m), 1.2, slide_from=0.95, release=0.5, seed=i), i * 0.9, 0.5)
    tr.place(taiko(1.5, 48, 1.0), 0.0, 0.7)
    tr.place(taiko(1.5, 44, 1.0), 3.6, 0.7)
    tr.place(gong(70.0, 3.0), 3.6, 0.45)
    tr.reverb(2.5, 0.4, seed=23)
    x = tr.finish(0.1)
    fade = np.minimum(1.0, np.linspace(1, 0, len(x)) * 5)
    return x * fade


# ------------------------------------------------------------------ sfx
def sfx_norm(x, peak=0.8):
    x = x - np.mean(x)
    m = np.max(np.abs(x)) + 1e-9
    return x * peak / m


def make_sfx():
    rng = np.random.default_rng(3)
    out = {}
    out["sfx_select"] = sfx_norm(woodblock(0.09, 1500), 0.5)
    c = np.zeros(int(0.5 * SR))
    for i, m in enumerate([76, 83]):
        s = pluck(hz(m), 0.4, 0.6, 5.0, i)
        c[int(i * 0.07 * SR):int(i * 0.07 * SR) + len(s)] += s[:len(c) - int(i * 0.07 * SR)]
    out["sfx_confirm"] = sfx_norm(c, 0.6)
    n = int(0.35 * SR)
    t = tt(n)
    hit = fir_lowpass(rng.standard_normal(n), 3000) * np.exp(-t * 28) + np.sin(2 * np.pi * 95 * (1 + 1.2 * np.exp(-t * 30)) * t) * np.exp(-t * 14)
    out["sfx_hit"] = sfx_norm(hit, 0.85)
    n = int(0.9 * SR)
    t = tt(n)
    clang = np.zeros(n)
    for k, a in [(1.0, 1.0), (2.76, 0.7), (5.4, 0.5), (8.9, 0.35)]:
        clang += a * np.sin(2 * np.pi * 820 * k * t) * np.exp(-t * (6 + 3 * k))
    clang += fir_highpass(rng.standard_normal(n), 3000) * np.exp(-t * 55) * 0.6
    out["sfx_counter"] = sfx_norm(clang, 0.8)
    n = int(1.4 * SR)
    pf = np.zeros(n)
    for i, m in enumerate([84, 88, 91, 96]):
        s = pluck(hz(m), 1.2, 0.85, 3.0, i)
        o = int(i * 0.07 * SR)
        pf[o:o + len(s)] += s[:n - o]
    t = tt(n)
    pf += fir_highpass(rng.standard_normal(n), 5000) * np.exp(-t * 6) * 0.15
    out["sfx_perfect"] = sfx_norm(pf, 0.8)
    n = int(0.9 * SR)
    t = tt(n)
    f = 700 * np.exp(-t * 1.3)
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.04 * np.sin(2 * np.pi * 22 * t))) / SR
    out["sfx_stun"] = sfx_norm(np.sin(ph) * np.exp(-t * 3), 0.7)
    heal = np.zeros(int(1.2 * SR))
    for i, m in enumerate([72, 76, 79, 84]):
        s = flute(hz(m), 0.5, breath=0.06, attack=0.04, release=0.2, seed=i)
        o = int(i * 0.12 * SR)
        heal[o:o + len(s)] += s[:len(heal) - o]
    out["sfx_heal"] = sfx_norm(heal, 0.6)
    pk = np.zeros(int(0.8 * SR))
    for i, m in enumerate([88, 95]):
        s = pluck(hz(m), 0.6, 0.7, 5.0, i)
        o = int(i * 0.09 * SR)
        pk[o:o + len(s)] += s[:len(pk) - o]
    out["sfx_pickup"] = sfx_norm(pk, 0.6)
    n = int(0.8 * SR)
    t = tt(n)
    thud = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 12) + fir_lowpass(rng.standard_normal(n), 900) * np.exp(-t * 30) * 0.8
    creak = fir_bandpass(rng.standard_normal(n), 300, 1400) * np.sin(np.pi * np.clip(t / 0.5, 0, 1)) * (t < 0.5) * 0.18
    out["sfx_door"] = sfx_norm(thud + creak, 0.8)
    n = int(0.5 * SR)
    t = tt(n)
    foot = fir_lowpass(rng.standard_normal(n), 1800) * np.exp(-t * 55)
    out["sfx_step"] = sfx_norm(foot, 0.35)
    return out


TRACKS = {
    "music_town": make_town,
    "music_tavern": make_tavern,
    "music_tavern_brawl": make_tavern_brawl,
    "music_forest": make_forest,
    "amb_forest_birds": make_forest_birds,
    "music_title": make_title,
    "music_battle": make_battle,
    "music_battle_boss": make_battle_boss,
    "jingle_victory": make_victory,
    "jingle_defeat": make_defeat,
}


def main():
    wanted = sys.argv[1:]
    for name, fn in TRACKS.items():
        if wanted and name not in wanted:
            continue
        write_wav(name, fn())
    if not wanted or "sfx" in wanted:
        for name, x in make_sfx().items():
            write_wav(name, x)


if __name__ == "__main__":
    main()

"""Turn AI-generated music (Suno etc.) into loop-ready runtime OGG files.

Usage (from the repo root):

    py -3 godot/tools/process_music.py <input> <output-name> [--loop|--once]
        [--lufs -18] [--xfade 3.0] [--trim] [--max-seconds 240]
    py -3 godot/tools/process_music.py --selftest

Reads MP3/WAV/FLAC/OGG through soundfile, converts to stereo 44.1 kHz, normalises
integrated loudness (pyloudnorm), optionally folds the tail into the head with an
equal-power crossfade for a seamless loop, peak-limits to -1 dBFS without hard
clipping and writes OGG/Vorbis to godot/assets/audio/<name>.ogg. Every run also
updates godot/assets/audio/music_manifest.json so the game knows which tracks loop.
"""
import argparse
import json
import math
import os
import shutil
import sys
import tempfile

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy.signal import resample_poly

SR = 44100
TARGET_PEAK_DB = -1.0
TRIM_SILENCE_DB = -50.0
ONCE_FADE_IN = 0.05
ONCE_FADE_OUT = 1.5
DEFAULT_LUFS = -18.0
DEFAULT_XFADE = 3.0
DEFAULT_MAX_SECONDS = 240.0
SEAM_LIMIT = 0.05

AUDIO_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
)
MANIFEST_NAME = "music_manifest.json"
# Checked-in OGG fixture for godot/tests/test_music_pipeline.gd. Regenerate with
#   py -3 godot/tools/process_music.py --selftest --write-fixture
FIXTURE_PATH = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "music_fixture.ogg")
)


# ------------------------------------------------------------------ audio prep
def load_audio(path):
    if not os.path.isfile(path):
        raise ValueError("input file not found: %s" % path)
    try:
        data, sr = sf.read(path, always_2d=True)
    except Exception as exc:  # soundfile raises LibsndfileError (RuntimeError)
        raise ValueError("cannot decode %s: %s" % (path, exc))
    if data.size == 0:
        raise ValueError("input file is empty: %s" % path)
    return data, int(sr)


def to_stereo(x):
    if x.shape[1] == 1:
        return np.repeat(x, 2, axis=1)
    if x.shape[1] == 2:
        return x
    mono = np.mean(x, axis=1, keepdims=True)
    return np.repeat(mono, 2, axis=1)


def resample(x, sr_in, sr_out=SR):
    if sr_in == sr_out:
        return x
    factor = math.gcd(int(sr_in), int(sr_out))
    up = int(sr_out) // factor
    down = int(sr_in) // factor
    return resample_poly(x, up, down, axis=0)


def trim_silence(x, threshold_db=TRIM_SILENCE_DB):
    threshold = 10.0 ** (threshold_db / 20.0)
    loud = np.flatnonzero(np.max(np.abs(x), axis=1) > threshold)
    if loud.size == 0:
        raise ValueError("input is silent at or below %.0f dB" % threshold_db)
    return x[loud[0]:loud[-1] + 1]


def truncate(x, max_seconds):
    if max_seconds is None or max_seconds <= 0:
        return x
    limit = int(max_seconds * SR)
    return x[:limit] if x.shape[0] > limit else x


def measure_lufs(x):
    """Integrated loudness in LUFS, or None when the clip is too short for a block."""
    meter = pyln.Meter(SR)
    value = float(meter.integrated_loudness(x))
    return value if np.isfinite(value) else None


def normalize_loudness(x, target_lufs):
    lufs = measure_lufs(x)
    if lufs is None:
        print("warning: clip is too short for loudness measurement, normalisation skipped")
        return x
    return x * (10.0 ** ((target_lufs - lufs) / 20.0))


def limit_peak(x, peak_db=TARGET_PEAK_DB):
    ceiling = 10.0 ** (peak_db / 20.0)
    peak = float(np.max(np.abs(x)))
    if peak > ceiling:
        x = x * (ceiling / peak)
    return x


# ------------------------------------------------------------------ loop / once
def loop_crossfade(x, xfade, sr=SR):
    """Fold the tail into the head so the last sample flows into the first.

    y[0:xf] = x[0:xf] * sin(theta) + x[N-xf:N] * cos(theta), y = x[0:N-xf].
    Equal power keeps the blend from dipping in level.
    """
    n = x.shape[0]
    fade = int(round(xfade * sr))
    fade = min(fade, (n - 1) // 2)
    if fade < int(0.1 * sr):
        raise ValueError("audio is too short for a %.1fs loop crossfade" % xfade)
    theta = np.linspace(0.0, np.pi / 2.0, fade, endpoint=False)
    g_in = np.sin(theta)[:, None]
    g_out = np.cos(theta)[:, None]
    head = x[:fade] * g_in + x[n - fade:] * g_out
    return np.concatenate([head, x[fade:n - fade]], axis=0)


def once_fades(x, sr=SR):
    n = x.shape[0]
    fade_in = min(int(ONCE_FADE_IN * sr), n)
    fade_out = min(int(ONCE_FADE_OUT * sr), max(0, n - fade_in))
    y = x.copy()
    if fade_in > 0:
        y[:fade_in] *= np.linspace(0.0, 1.0, fade_in, endpoint=False)[:, None]
    if fade_out > 0:
        y[n - fade_out:] *= np.linspace(1.0, 0.0, fade_out, endpoint=False)[:, None]
    return y


def process(x, sr_in, loop=True, target_lufs=DEFAULT_LUFS, xfade=DEFAULT_XFADE,
            trim=False, max_seconds=DEFAULT_MAX_SECONDS):
    x = to_stereo(x)
    x = resample(x, sr_in)
    if trim:
        x = trim_silence(x)
    x = truncate(x, max_seconds)
    x = normalize_loudness(x, target_lufs)
    if loop:
        if xfade <= 0:
            raise ValueError("--xfade must be positive when using --loop")
        x = loop_crossfade(x, xfade)
    else:
        x = once_fades(x)
    return limit_peak(x)


# ------------------------------------------------------------------ output
def write_ogg(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # libsndfile encodes Vorbis at its built-in VBR quality (about 0.4).
    # Write in blocks: one big write overflows the stack on Windows for long tracks.
    data = np.clip(x, -1.0, 1.0)
    channels = 1 if data.ndim == 1 else data.shape[1]
    with sf.SoundFile(path, "w", samplerate=SR, channels=channels,
                      format="OGG", subtype="VORBIS") as out:
        block = 16384
        for start in range(0, len(data), block):
            out.write(data[start:start + block])


def update_manifest(manifest_path, name, entry):
    data = {}
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError) as exc:
            raise ValueError("cannot read %s: %s" % (manifest_path, exc))
        if not isinstance(data, dict):
            raise ValueError("%s must contain a JSON object" % manifest_path)
    data[name] = entry
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False, sort_keys=True)
        handle.write("\n")


def process_file(input_path, name, loop=True, target_lufs=DEFAULT_LUFS,
                 xfade=DEFAULT_XFADE, trim=False, max_seconds=DEFAULT_MAX_SECONDS,
                 audio_dir=AUDIO_DIR):
    if name == "" or os.sep in name or "/" in name or "\\" in name:
        raise ValueError("output name must be a bare file name: %r" % name)
    data, sr_in = load_audio(input_path)
    out = process(data, sr_in, loop, target_lufs, xfade, trim, max_seconds)
    out_path = os.path.join(audio_dir, name + ".ogg")
    write_ogg(out_path, out)
    seconds = round(out.shape[0] / float(SR), 3)
    lufs = measure_lufs(out)
    entry = {
        "loop": bool(loop),
        "seconds": seconds,
        "lufs": round(lufs, 1) if lufs is not None else None,
        "source": os.path.basename(input_path),
    }
    update_manifest(os.path.join(audio_dir, MANIFEST_NAME), name, entry)
    return {
        "path": out_path,
        "seconds": seconds,
        "lufs": lufs,
        "loop": bool(loop),
        "size": os.path.getsize(out_path),
        "audio": out,
    }


def print_summary(info):
    lufs = "n/a" if info["lufs"] is None else "%.1f LUFS" % info["lufs"]
    mode = "loop" if info["loop"] else "once"
    print("wrote %s  %.1fs  %s  %s  %.2f MB" % (
        info["path"], info["seconds"], lufs, mode, info["size"] / 1e6,
    ))


# ------------------------------------------------------------------ selftest
def _selftest_signal():
    t = np.arange(int(4.0 * SR)) / float(SR)
    rng = np.random.default_rng(7)
    mono = 0.28 * np.sin(2.0 * np.pi * 220.0 * t) + 0.005 * rng.standard_normal(t.size)
    return np.repeat(mono[:, None], 2, axis=1)


def selftest(write_fixture=False):
    target = DEFAULT_LUFS
    x = _selftest_signal()
    checks = []
    with tempfile.TemporaryDirectory(prefix="music_selftest_") as tmp:
        source = os.path.join(tmp, "selftest_input.wav")
        sf.write(source, x, SR)
        info = process_file(source, "selftest", loop=True, target_lufs=target,
                            xfade=1.0, max_seconds=DEFAULT_MAX_SECONDS, audio_dir=tmp)
        out = info["audio"]

        seam = float(np.max(np.abs(out[0] - out[-1])))
        checks.append((seam <= SEAM_LIMIT, "seam %.4f (limit %.2f)" % (seam, SEAM_LIMIT)))

        if info["lufs"] is None:
            checks.append((False, "loudness measurement failed"))
            lufs_text = "n/a"
        else:
            within = abs(info["lufs"] - target) <= 1.0
            checks.append((within, "lufs %.2f (target %.1f +/- 1)" % (info["lufs"], target)))
            lufs_text = "%.2f" % info["lufs"]

        with open(os.path.join(tmp, MANIFEST_NAME), "r", encoding="utf-8") as handle:
            manifest = json.load(handle)
        entry = manifest.get("selftest", {})
        checks.append((entry.get("loop") is True, "manifest marks the track as a loop"))
        checks.append((abs(float(entry.get("seconds", 0.0)) - 3.0) <= 0.01,
                       "manifest duration %.2fs" % float(entry.get("seconds", 0.0))))

        decoded, decoded_sr = sf.read(info["path"], always_2d=True)
        length_ok = abs(decoded.shape[0] / float(SR) - info["seconds"]) <= 0.05
        checks.append((decoded_sr == SR and length_ok,
                       "ogg decodes back (%.2fs)" % (decoded.shape[0] / float(decoded_sr))))

        if write_fixture:
            os.makedirs(os.path.dirname(FIXTURE_PATH), exist_ok=True)
            shutil.copyfile(info["path"], FIXTURE_PATH)
            print("fixture: wrote %s (%.1f KB)" % (
                FIXTURE_PATH, os.path.getsize(FIXTURE_PATH) / 1024.0,
            ))

    failed = [text for ok, text in checks if not ok]
    for ok, text in checks:
        print("  [%s] %s" % ("ok" if ok else "FAIL", text))
    print("selftest: seam=%.4f lufs=%s ogg=%.1f KB -> %s" % (
        seam, lufs_text, info["size"] / 1024.0, "OK" if not failed else "FAILED",
    ))
    return 0 if not failed else 1


# ------------------------------------------------------------------ cli
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert AI-generated music into loop-ready OGG for the game.",
    )
    parser.add_argument("input", nargs="?", help="MP3/WAV/FLAC/OGG input file")
    parser.add_argument("output", nargs="?", help="output name (writes <name>.ogg)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--loop", dest="loop", action="store_true",
                      help="seamless loop via equal-power tail/head crossfade (default)")
    mode.add_argument("--once", dest="loop", action="store_false",
                      help="one-shot cue: 0.05s fade-in, 1.5s fade-out, no loop")
    parser.set_defaults(loop=True)
    parser.add_argument("--lufs", type=float, default=DEFAULT_LUFS,
                        help="target integrated loudness (default -18)")
    parser.add_argument("--xfade", type=float, default=DEFAULT_XFADE,
                        help="loop crossfade seconds (default 3.0)")
    parser.add_argument("--trim", action="store_true",
                        help="trim leading/trailing silence below -50 dB")
    parser.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS,
                        help="truncate longer inputs (default 240)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the built-in signal checks and exit")
    parser.add_argument("--write-fixture", action="store_true",
                        help="with --selftest, refresh tests/fixtures/music_fixture.ogg")
    args = parser.parse_args(argv)

    if args.write_fixture and not args.selftest:
        parser.error("--write-fixture is only valid together with --selftest")
    if args.selftest:
        return selftest(write_fixture=args.write_fixture)
    if not args.input or not args.output:
        parser.error("usage: process_music.py <input> <output-name> [--loop|--once] "
                     "or process_music.py --selftest")
    try:
        info = process_file(
            args.input, args.output, loop=args.loop, target_lufs=args.lufs,
            xfade=args.xfade, trim=args.trim, max_seconds=args.max_seconds,
        )
    except ValueError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1
    print_summary(info)
    return 0


if __name__ == "__main__":
    sys.exit(main())

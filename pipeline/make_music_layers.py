"""Build the adaptive music layers that play in sync on top of a shift's music track:
  <track>_peak.ogg    rush hour: shaker 16ths, claps on the backbeat, a bongo pattern
  <track>_final.ogg   the last seconds of a shift: a tick-tock on every beat, shaker 8ths
Each layer is exactly as long as its track (same sample count), so Godot's
AudioStreamSynchronized keeps them locked together across loops.

The beats come from the track itself: spectral-flux onsets -> tempo by autocorrelation ->
dynamic-programming beat tracking (Ellis 2007), so the hits follow the music even where the
loop crossfade (gen_audio.make_loop) bends the grid. Which beats are the backbeat (2 and 4)
is guessed from where the track's own snare/claps are loudest.

The one-shot drum samples are ElevenLabs sound effects (pipeline/audio_cues.json perc_*,
made by gen_audio.py into art_src/audio_raw/sfx/).

Usage (repo root):  python pipeline/make_music_layers.py [track ...]   (default: bgm_run bgm_trial)
                    python pipeline/make_music_layers.py --preview      also writes preview mixes
"""
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MUSIC = os.path.join(ROOT, "game", "assets", "audio", "music")
RAW = os.path.join(ROOT, "art_src", "audio_raw", "sfx")
PREVIEW = os.path.join(ROOT, "art_src", "audio_preview")
SR = 44100


def decode(path: str, sr: int = SR, ch: int = 1) -> np.ndarray:
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    a = np.frombuffer(out, dtype=np.float32)
    return a.reshape(-1, ch) if ch > 1 else a


def encode(a: np.ndarray, path: str, sr: int = SR) -> None:
    """Float stereo -> OGG (or MP3 for previews, by the extension)."""
    codec = ["-c:a", "libvorbis", "-q:a", "5"] if path.endswith(".ogg") else ["-c:a", "libmp3lame", "-q:a", "3"]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ac", "2", "-ar", str(sr), "-i", "-", *codec, path],
                   input=np.ascontiguousarray(a, dtype=np.float32).tobytes(), check=True)


# ---------------------------------------------------------------- beat tracking

HOP = 256
FR = 22050 / HOP   # onset frames per second


def onset_envelope(mono22: np.ndarray) -> np.ndarray:
    n = 2048
    win = np.hanning(n)
    frames = np.lib.stride_tricks.sliding_window_view(mono22, n)[::HOP] * win
    mag = np.log1p(100.0 * np.abs(np.fft.rfft(frames, axis=1)))
    flux = np.maximum(np.diff(mag, axis=0), 0.0).sum(axis=1)
    flux = np.concatenate([[0.0], flux])
    k = int(FR * 0.5)
    local = np.convolve(flux, np.ones(k) / k, mode="same")
    env = np.maximum(flux - local, 0.0)
    return env / (env.std() + 1e-9)


def tempo(env: np.ndarray, lo: float = 70.0, hi: float = 190.0, prior: float = 120.0) -> float:
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    best, best_bpm = -1.0, prior
    for bpm in np.arange(lo, hi, 0.05):
        lag = FR * 60.0 / bpm
        # score the lag and its multiples (a real tempo also lines up at 2 and 4 beats)
        s = sum(np.interp(lag * m, np.arange(len(ac)), ac) / m for m in (1, 2, 4))
        s *= np.exp(-0.5 * (np.log2(bpm / prior) / 1.0) ** 2)   # gentle preference for ~120
        if s > best:
            best, best_bpm = s, bpm
    return float(best_bpm)


def track_beats(env: np.ndarray, bpm: float, tightness: float = 300.0) -> np.ndarray:
    period = FR * 60.0 / bpm
    n = len(env)
    score = env.copy()
    back = np.full(n, -1)
    lo, hi = int(round(period / 2)), int(round(period * 2))
    for t in range(hi, n):
        prev = np.arange(t - hi, t - lo)
        pen = -tightness * np.log((t - prev) / period) ** 2
        cand = score[prev] + pen
        j = int(np.argmax(cand))
        score[t] = env[t] + cand[j]
        back[t] = prev[j]
    # best end within the last beat period, then walk back
    t = int(n - period + np.argmax(score[int(n - period):]))
    beats = []
    while t >= 0:
        beats.append(t)
        t = back[t]
    return np.array(beats[::-1], dtype=float) / FR   # seconds


def align(mono22: np.ndarray, beats: np.ndarray) -> float:
    """Seconds to add to the tracked beats so they sit on the track's drum attacks: an onset
    frame is reported before its transient (the analysis window reaches it early), so measure
    where the 2-8 kHz energy rises fastest, averaged over all beats."""
    from scipy.signal import butter, sosfilt
    hi = np.abs(sosfilt(butter(4, [2000, 8000], "band", fs=22050, output="sos"), mono22))
    hi = np.convolve(hi, np.ones(44) / 44, mode="same")   # 2 ms smoothing
    offs = np.arange(-0.03, 0.15, 0.001)
    prof = np.array([np.mean([hi[int((b + o) * 22050)] for b in beats[1:-2]]) for o in offs])
    return float(offs[int(np.argmax(np.diff(prof)))])


def backbeat_parity(mono22: np.ndarray, beats: np.ndarray) -> int:
    """0 or 1: which beats (even or odd index) carry the snare/clap, i.e. are beats 2 and 4."""
    def band_ratio(t: float) -> float:
        i = int(t * 22050)
        seg = mono22[i:i + 1024]
        if len(seg) < 1024:
            return 0.0
        spec = np.abs(np.fft.rfft(seg * np.hanning(1024)))
        f = np.fft.rfftfreq(1024, 1 / 22050)
        return spec[(f > 1500) & (f < 6000)].sum() / (spec[f < 160].sum() + 1e-9)
    r = np.array([band_ratio(t) for t in beats])
    return 0 if r[0::2].mean() > r[1::2].mean() else 1


# ---------------------------------------------------------------- samples and layers

def sample(name: str, start: float = 0.0, length: float = 0.2, pitch: float = 1.0) -> np.ndarray:
    a = decode(os.path.join(RAW, f"{name}.mp3"))
    # skip the silence before the hit, then cut and fade the tail
    th = np.abs(a).max() * 0.1
    on = int(np.argmax(np.abs(a) > th))
    a = a[on + int(start * SR):on + int((start + length) * SR)].astype(np.float64)
    if pitch != 1.0:   # resample: a higher pitch is also a shorter hit, which suits drums
        a = np.interp(np.arange(0, len(a), pitch), np.arange(len(a)), a)
    fade = min(len(a) // 3, int(0.04 * SR))
    a[-fade:] *= np.linspace(1.0, 0.0, fade)
    a[:32] *= np.linspace(0.0, 1.0, 32)
    return a / (np.abs(a).max() + 1e-9)


def place(buf: np.ndarray, s: np.ndarray, t: float, gain_db: float, pan: float = 0.0) -> None:
    i = int(round(t * SR))
    if i >= len(buf):
        return
    s = s[:len(buf) - i] * 10 ** (gain_db / 20)
    buf[i:i + len(s), 0] += s * np.sqrt(0.5 * (1 - pan))
    buf[i:i + len(s), 1] += s * np.sqrt(0.5 * (1 + pan))


def subdivide(beats: np.ndarray, n: int, total: float) -> list:
    """Times of every 1/n beat, interpolated between tracked beats; [(time, beat_index, step)]."""
    out = []
    for b in range(len(beats)):
        nxt = beats[b + 1] if b + 1 < len(beats) else beats[b] + (beats[b] - beats[b - 1])
        for k in range(n):
            t = beats[b] + (nxt - beats[b]) * k / n
            if t < total:
                out.append((t, b, k))
    return out


def humanize(rng: np.random.Generator, ms: float = 4.0) -> float:
    return rng.normal(0.0, ms / 1000.0)


def build(track: str, preview: bool) -> None:
    path = os.path.join(MUSIC, f"{track}.ogg")
    base = decode(path, SR, 2)
    total = len(base) / SR
    mono22 = decode(path, 22050)
    env = onset_envelope(mono22)
    bpm = tempo(env)
    beats = track_beats(env, bpm)
    shift = align(mono22, beats)
    beats = beats + shift
    ib = np.diff(beats)
    par = backbeat_parity(mono22, beats)
    print(f"{track}: {total:.1f}s, {bpm:.1f} bpm, {len(beats)} beats, interval {ib.mean() * 1000:.0f}+-{ib.std() * 1000:.0f} ms, "
          f"shifted {shift * 1000:+.0f} ms, backbeat parity {par}")
    rng = np.random.default_rng(7)

    shaker = sample("perc_shaker", length=0.09)
    clap = sample("perc_clap", length=0.18)
    bongo_hi = sample("perc_bongo", length=0.22, pitch=1.12)
    bongo_lo = sample("perc_bongo", length=0.28, pitch=0.84)
    tick = sample("perc_block", length=0.12, pitch=1.25)
    tock = sample("perc_block", length=0.14, pitch=0.94)

    # --- peak: busy kitchen groove
    peak = np.zeros((len(base), 2))
    for t, b, k in subdivide(beats, 4, total):
        gain = -15.0 if k == 2 else (-21.0 if k in (1, 3) else -18.0)   # 8th-note offbeat accent
        place(peak, shaker, t + humanize(rng), gain + rng.normal(0, 1.0), pan=0.35)
        backbeat = (b % 2) == par
        if k == 0 and backbeat:
            place(peak, clap, t + humanize(rng, 3), -9.0, pan=-0.1)
        bar_pos = ((b - par + 1) % 4) * 4 + k   # 0..15 within a 4-beat bar (beat 1 = a non-backbeat)
        if bar_pos in (3, 6, 10, 14):
            place(peak, bongo_hi, t + humanize(rng), -11.0, pan=-0.4)
        elif bar_pos in (0, 8, 11):
            place(peak, bongo_lo, t + humanize(rng), -10.0, pan=-0.3)

    # --- final: the clock is running
    final = np.zeros((len(base), 2))
    for t, b, k in subdivide(beats, 2, total):
        if k == 0:
            place(final, tick if b % 2 == 0 else tock, t, -3.0, pan=0.15 if b % 2 == 0 else -0.15)
        else:
            place(final, shaker, t + humanize(rng), -13.0, pan=0.3)

    for name, layer in (("peak", peak), ("final", final)):
        layer = np.clip(layer, -0.98, 0.98)
        encode(layer, os.path.join(MUSIC, f"{track}_{name}.ogg"))
        if preview:
            os.makedirs(PREVIEW, exist_ok=True)
            a, b = int(20 * SR), int(40 * SR)
            mix = (base[a:b] + layer[a:b]) * 0.5   # as in the game: both at 0 dB
            fade = int(SR * 0.6)
            mix[:fade] *= np.linspace(0, 1, fade)[:, None]
            mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
            encode(mix, os.path.join(PREVIEW, f"{track}_{name}.mp3"))
    if preview:
        encode(base[int(20 * SR):int(40 * SR)] * 0.5, os.path.join(PREVIEW, f"{track}_plain.mp3"))


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for track in args or ["bgm_run", "bgm_trial"]:
        build(track, "--preview" in sys.argv)


if __name__ == "__main__":
    main()

"""Render short "what it sounds like in play" demos of the mix (Audio autoload) for review pages:
the game's own files, mixed offline the way the game mixes them (same volumes, layers, ducking,
speed-up, low-pass). Output: art_src/audio_preview/demo_*.mp3 and catch_*.mp3.

Usage (repo root):  python pipeline/render_sound_demos.py
"""
import os
import sys

import numpy as np
from scipy.signal import butter, sosfilt

sys.path.insert(0, os.path.dirname(__file__))
from make_music_layers import SR, decode, encode  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
A = os.path.join(ROOT, "game", "assets", "audio")
OUT = os.path.join(ROOT, "art_src", "audio_preview")
# Settings defaults (bus volumes) and the music player's own volume
BUS = {"Music": 20 * np.log10(0.7) - 6.0, "SFX": 20 * np.log10(0.8), "Voice": 20 * np.log10(0.9)}
db = lambda x: 10 ** (x / 20)


def snd(path: str) -> np.ndarray:
    return decode(path, SR, 2).astype(np.float64)


def sfx(name: str) -> np.ndarray:
    return snd(os.path.join(A, "sfx", name + ".wav"))


def vo(name: str) -> np.ndarray:
    return snd(os.path.join(A, "voice", name + ".ogg"))


class Mix:
    def __init__(self, seconds: float):
        self.n = int(seconds * SR)
        self.bed = np.zeros((self.n, 2))     # SFXBed
        self.key = np.zeros((self.n, 2))     # stingers, straight into SFX
        self.voice = np.zeros((self.n, 2))
        self.keys = []                       # (start, end) of stingers

    def add(self, buf, s, t, gain_db, cut_at=None):
        i = int(t * SR)
        s = s[: self.n - i] * db(gain_db)
        if cut_at is not None:              # a voice line cut off by the next one (10 ms fade)
            k = int((cut_at - t) * SR)
            if k < len(s):
                s = s.copy()
                f = min(441, len(s) - k)
                s[k:k + f] *= np.linspace(1, 0, f)[:, None]
                s[k + f:] = 0
        buf[i:i + len(s)] += s

    def sfx(self, name, t, gain_db, key=False):
        s = sfx(name)
        self.add(self.key if key else self.bed, s, t, gain_db)
        if key:
            self.keys.append((t, t + min(len(s) / SR, 2.5)))

    def duck_curve(self, depth_db, enabled=True):
        """The SFXBed / music gain under stingers: 30 ms attack, 350 ms release (Audio._process)."""
        g = np.zeros(self.n)
        if not enabled:
            return np.ones(self.n)
        target = np.zeros(self.n)
        for a, b in self.keys:
            target[int(a * SR):int(b * SR)] = depth_db
        cur, dt = 0.0, 1 / SR
        ka, kr = 1 - np.exp(-dt / 0.03), 1 - np.exp(-dt / 0.35)
        for i in range(self.n):   # fine at these lengths
            cur += (target[i] - cur) * (ka if target[i] < cur else kr)
            g[i] = cur
        return db(g)


def music(track: str, start: float, seconds: float, rate=None):
    """The track and its layers from `start`; `rate`: per-output-sample playback speed (pitch)."""
    parts = [snd(os.path.join(A, "music", f"{track}{s}.ogg")) for s in ("", "_peak", "_final")]
    n = int(seconds * SR)
    if rate is None:
        pos = start * SR + np.arange(n)
    else:
        pos = start * SR + np.concatenate([[0.0], np.cumsum(rate[:-1])])
    out = []
    for p in parts:
        idx = np.arange(len(p))
        out.append(np.stack([np.interp(pos, idx, p[:, c]) for c in (0, 1)], axis=1))
    return out


def ramp(n, points):
    """Piecewise-linear envelope from [(seconds, value)]."""
    t = np.arange(n) / SR
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def finish(m: Mix, mus: np.ndarray, name: str, duck=True):
    g = m.duck_curve(-4.0, duck)[:, None]
    out = mus * db(BUS["Music"]) * g + (m.bed * g + m.key) * db(BUS["SFX"]) + m.voice * db(BUS["Voice"])
    peak = np.abs(out).max()
    if peak > 0.95:   # Master hard limiter, roughly
        out *= 0.95 / peak
    f = int(0.3 * SR)
    out[-f:] *= np.linspace(1, 0, f)[:, None]
    encode(out, os.path.join(OUT, name + ".mp3"))
    print(name)


def catches(m: Mix, t0, t1, every, kinds, rng):
    t = t0
    while t < t1:
        m.sfx(rng.choice(kinds), t + rng.uniform(-0.05, 0.05), -1.0)
        t += every


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(3)
    soft = ["catch_v1", "catch_v2"]
    allk = soft + [f"catch_{k}_v{v}" for k in ("crisp", "slosh", "saucy", "wobble") for v in (1, 2)]

    # each catch sound alone
    for f in sorted(os.listdir(os.path.join(A, "sfx"))):
        if f.startswith(("catch", "combo")) and f.endswith(".wav"):
            encode(sfx(f[:-4]) * db(-1.0), os.path.join(OUT, f[:-4] + ".mp3"))
    # a gold dish: its landing sound with the sparkle on top
    m = Mix(1.2)
    m.sfx("catch_v1", 0.0, -1.0)
    m.sfx("catch_gold", 0.0, -9.0)
    finish(m, np.zeros((m.n, 2)), "catch_gold_dish")

    # 1. rush hour: plain, then the bell + 梁阿姨 + the drum layer, then back
    L = 16.0
    m = Mix(L)
    base, peak, final = music("bgm_run", 20.0, L)
    mus = base + peak * ramp(m.n, [(0, 0), (4.0, 0), (4.6, 1), (12.0, 1), (13.6, 0)])[:, None]
    m.sfx("peak_start", 4.0, -4.0, key=True)
    m.add(m.voice, vo("auntie_rush_v1"), 4.1, 0.0)
    catches(m, 0.8, 4.0, 0.9, allk, rng)
    catches(m, 4.6, 12.0, 0.36, allk, rng)       # she cooks 2.5x faster
    m.sfx("peak_end", 12.0, -4.0)
    catches(m, 12.5, 15.5, 0.9, allk, rng)
    finish(m, mus, "demo_peak")

    # 2. the last 10 seconds: ticking clock + speed-up, then the shutter, the music steps back
    L = 17.0
    m = Mix(L)
    rate = ramp(m.n, [(0, 1.0), (3.0, 1.0), (13.0, 1.05), (13.4, 1.0)])
    base, peak, final = music("bgm_run", 30.0, L, rate)
    mus = base + final * ramp(m.n, [(0, 0), (3.0, 0), (3.6, 1), (13.0, 1), (14.6, 0)])[:, None]
    mus *= db(ramp(m.n, [(0, 0), (13.0, 0), (13.3, -7.0), (L, -7.0)]))[:, None]
    catches(m, 0.5, 13.0, 0.7, allk, rng)
    m.sfx("shift_closed", 13.0, -3.0, key=True)
    m.add(m.voice, vo("fish_full_v1"), 13.2, 0.0)
    finish(m, mus, "demo_final")

    # 3. 深度思考: hold -> the music slows and muffles, release -> back
    L = 12.0
    m = Mix(L)
    slow = ramp(m.n, [(0, 0), (3.0, 0), (3.6, 1), (8.0, 1), (8.9, 0)])
    rate = 1.0 - 0.06 * slow
    base, peak, final = music("bgm_run", 40.0, L, rate)
    lp = np.stack([sosfilt(butter(2, 1400, "low", fs=SR, output="sos"), base[:, c]) for c in (0, 1)], axis=1)
    mus = base * (1 - slow[:, None]) + lp * slow[:, None]
    m.sfx("think_start", 3.0, -6.0)
    m.sfx("think_end", 8.0, -6.0)
    catches(m, 0.5, 3.0, 0.8, allk, rng)
    catches(m, 3.6, 8.0, 1.4, allk, rng)       # the food falls slowly
    catches(m, 8.6, 11.5, 0.8, allk, rng)
    finish(m, mus, "demo_think")

    # 4. a new recipe in the middle of a busy box: without / with the ducking
    for duck in (False, True):
        r = np.random.default_rng(5)
        L = 7.0
        m = Mix(L)
        base, _, _ = music("bgm_run", 50.0, L)
        catches(m, 0.3, 6.5, 0.22, allk, r)
        t = 0.4
        while t < 6.5:
            m.sfx(f"chomp_v{r.integers(1, 5)}", t, -4.0)
            t += 0.42
        m.sfx("version_up", 2.5, -6.0, key=True)
        mus = base * (m.duck_curve(-4.0, duck)[:, None])
        finish(m, mus, "demo_duck_" + ("on" if duck else "off"), duck)

    # 5. two voices at once: before (both talk) / now (one line at a time)
    for one in (False, True):
        L = 4.0
        m = Mix(L)
        base, _, _ = music("bgm_run", 24.0, L)
        a = vo("auntie_care_v1")
        m.add(m.voice, a, 0.3, 0.0, cut_at=1.1 if one else None)
        m.add(m.voice, vo("fish_spit_v1"), 1.1, 0.0)
        m.sfx("veg_reject", 1.1, -8.0)
        finish(m, base, "demo_voice_" + ("one" if one else "both"))

    # the tracks plain / with each layer, 20 s (make_music_layers --preview made these too)


if __name__ == "__main__":
    main()

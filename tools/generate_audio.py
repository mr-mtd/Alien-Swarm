#!/usr/bin/env python3
"""Generates every sound in res://audio/ from code, so nothing licensed or downloaded is needed.

    python3 tools/generate_audio.py

Needs Python 3 with numpy, plus ffmpeg (built with libvorbis) on the PATH for the music .ogg.
Change SEED, or any of the numbers below, and re-run to get a different take.
"""

import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
SEED = 7
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")


# --- helpers -------------------------------------------------------------------------------------

def midi_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def seconds(n):
    return np.arange(n) / SR


def write_wav(path, samples):
    """Writes mono (1-D) or stereo (N x 2) float samples in -1..1 as 16-bit PCM."""
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as f:
        f.setnchannels(1 if data.ndim == 1 else data.shape[1])
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def normalize(x, peak_db=-1.0):
    return x * (10.0 ** (peak_db / 20.0) / np.max(np.abs(x)))


def fade_edges(x, fade_in=0.002, fade_out=0.02):
    n_in, n_out = int(fade_in * SR), int(fade_out * SR)
    x = x.copy()
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return x


def svf(x, cutoff, q=0.7):
    """Chamberlin state-variable filter with a per-sample cutoff. Returns (low, band, high)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    f = 2.0 * np.sin(np.pi * np.minimum(cutoff, SR / 6.0) / SR)
    damp = 1.0 / q
    low = band = 0.0
    lo, bp, hp = np.zeros_like(x), np.zeros_like(x), np.zeros_like(x)
    for i in range(len(x)):
        high = x[i] - low - damp * band
        band += f[i] * high
        low += f[i] * band
        lo[i], bp[i], hp[i] = low, band, high
    return lo, bp, hp


def sweep(n, points):
    """Piecewise-exponential curve through (time_s, value) points, sampled n times."""
    t = seconds(n)
    times, values = zip(*points)
    return np.exp(np.interp(t, times, np.log(values)))


def sine_sweep(n, points):
    """A sine whose frequency follows sweep(points), with continuous phase."""
    return np.sin(2.0 * np.pi * np.cumsum(sweep(n, points)) / SR)


def env(n, attack, decay):
    """Linear attack then exponential decay (decay is the time constant in seconds)."""
    t = seconds(n)
    return np.where(t < attack, t / max(attack, 1e-6), np.exp(-(t - attack) / decay))


def fft_filter(x, low_hz=None, high_hz=None):
    """Brick-ish (smoothed) circular filter in the frequency domain. Loop-safe for music."""
    spectrum = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(x.shape[0], 1.0 / SR)
    mask = np.ones_like(freqs)
    if high_hz is not None:
        mask *= 1.0 / (1.0 + (freqs / high_hz) ** 4)
    if low_hz is not None:
        mask *= 1.0 / (1.0 + (low_hz / np.maximum(freqs, 1e-3)) ** 4)
    if x.ndim == 2:
        mask = mask[:, None]
    return np.fft.irfft(spectrum * mask, n=x.shape[0], axis=0)


# --- sound effects -------------------------------------------------------------------------------

def player_attack(rng):
    """Claw swing: a whoosh that peaks 0.12 s in, with a low thump of weight at the same moment."""
    n = int(0.42 * SR)
    t = seconds(n)
    noise = rng.uniform(-1.0, 1.0, n)
    _, whoosh, _ = svf(noise, sweep(n, [(0, 350), (0.12, 2600), (0.42, 600)]), q=1.1)
    whoosh *= np.interp(t, [0, 0.10, 0.13, 0.42], [0, 0.9, 1.0, 0]) ** 1.5
    _, _, air = svf(noise, 5000.0, q=0.7)
    air *= np.interp(t, [0, 0.11, 0.2, 0.42], [0, 0.25, 0.05, 0])
    weight = np.zeros(n)
    hit = int(0.10 * SR)
    m = n - hit
    weight[hit:] = sine_sweep(m, [(0, 120), (0.15, 50), (1, 45)]) * env(m, 0.01, 0.09) * 0.8
    return fade_edges(normalize(whoosh * 1.3 + air + weight, -1.0))


def enemy_hit(rng):
    """Claws biting into an alien: a crunch on top of a fleshy thud, then a wet squelch."""
    n = int(0.45 * SR)
    t = seconds(n)
    thud = sine_sweep(n, [(0, 100), (0.2, 42), (1, 40)]) * env(n, 0.003, 0.11)
    # Crunch: crackly grains of filtered noise, overdriven.
    grains = (rng.uniform(0, 1, n) > 0.92) * rng.uniform(-1, 1, n)
    _, crunch, _ = svf(grains + rng.uniform(-0.3, 0.3, n), 2200.0, q=1.2)
    crunch = np.tanh(crunch * 6.0) * env(n, 0.001, 0.035)
    # Squelch: a resonant band that wobbles like something wet moving.
    wobble = sweep(n, [(0, 900), (0.08, 350), (0.3, 220), (0.45, 200)]) * (1 + 0.45 * np.sin(2 * np.pi * 23 * t))
    _, squelch, _ = svf(rng.uniform(-1, 1, n), wobble, q=4.0)
    squelch *= np.interp(t, [0, 0.02, 0.08, 0.32, 0.45], [0, 0.6, 1.0, 0.15, 0])
    glorp = sine_sweep(n, [(0, 420), (0.25, 140), (1, 120)])
    glorp *= np.interp(t, [0, 0.03, 0.1, 0.3, 0.45], [0, 0.0, 0.35, 0, 0]) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * t))
    mix = thud * 1.0 + crunch * 0.55 + squelch * 0.9 + glorp
    return fade_edges(normalize(np.tanh(mix * 1.4), -1.0))


def player_hit(rng):
    """The Strider gets struck: a sharp armoured clang and impact, then a pained low groan."""
    n = int(0.6 * SR)
    t = seconds(n)
    _, _, snap = svf(rng.uniform(-1, 1, n), 2500.0, q=0.7)
    snap *= env(n, 0.0005, 0.012)
    ring = sum(
        a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
        for f, a, d in [(830, 0.5, 0.12), (1312, 0.35, 0.09), (2167, 0.25, 0.06), (3371, 0.15, 0.04)]
    )
    body = sine_sweep(n, [(0, 150), (0.12, 60), (1, 55)]) * env(n, 0.002, 0.09)
    # Groan: a buzzy tone, falling in pitch, through two vowel formants ("oh").
    pitch = sweep(n, [(0, 104), (0.15, 96), (0.6, 74)]) * (1 + 0.012 * np.sin(2 * np.pi * 6.5 * t))
    phase = np.cumsum(pitch) / SR
    buzz = 2.0 * (phase % 1.0) - 1.0
    _, f1, _ = svf(buzz, 480.0, q=5.0)
    _, f2, _ = svf(buzz, 850.0, q=6.0)
    groan = (f1 + 0.6 * f2) * np.interp(t, [0, 0.03, 0.08, 0.35, 0.6], [0, 0, 1, 0.6, 0])
    groan /= np.max(np.abs(groan))
    mix = snap * 0.9 + ring * 0.5 + body * 0.8 + groan * 0.55
    return fade_edges(normalize(mix, -1.0), fade_out=0.05)


def enemy_attack(rng):
    """Alien screech and chitter as an enemy lunges. Played pitched down for the Duskmane."""
    n = int(0.42 * SR)
    t = seconds(n)
    carrier = sweep(n, [(0, 700), (0.1, 1500), (0.42, 650)])
    index = np.interp(t, [0, 0.1, 0.42], [1.0, 3.5, 1.5])
    mod_phase = np.cumsum(carrier * 1.41) / SR
    car_phase = np.cumsum(carrier) / SR
    screech = np.sin(2 * np.pi * car_phase + index * np.sin(2 * np.pi * mod_phase))
    chitter = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 34 * t))
    _, rasp, _ = svf(rng.uniform(-1, 1, n), carrier * 2.0, q=2.0)
    shape = np.interp(t, [0, 0.03, 0.12, 0.42], [0, 1, 0.8, 0])
    mix = (screech * chitter * 0.8 + rasp * 0.5) * shape
    _, smooth, _ = svf(mix, 6000.0, q=0.7)  # Takes the fizz off the square-wave chitter.
    return fade_edges(normalize(smooth, -1.0), fade_out=0.04)


# --- music ---------------------------------------------------------------------------------------

BPM = 80.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 24
LENGTH = BARS * BAR  # 72 s, loops seamlessly.
N = int(round(LENGTH * SR))
TAIL = int(10 * SR)  # Room for notes to ring past the loop point; folded back onto the start.

# E phrygian with the odd tritone thrown in: one chord every four bars.
CHORDS = [
    [40, 47, 53, 55],  # E  B  F  G   (Em with a flat ninth)
    [41, 48, 52, 57],  # F  C  E  A   (Fmaj7)
    [38, 45, 53, 60],  # D  A  F  C   (Dm7)
    [34, 41, 50, 57],  # Bb F  D  A   (a tritone away from home)
    [36, 43, 52, 59],  # C  G  E  B   (Cmaj7)
    [40, 47, 53, 58],  # E  B  F  Bb  (unresolved, falls back into the top)
]
SCALE = [40, 41, 43, 45, 46, 47, 48, 50]  # E F G A Bb B C D


def loop_hz(f):
    """Rounds a steady frequency so it completes a whole number of cycles per loop."""
    return round(f * LENGTH) / LENGTH


def gain_curve(points):
    """Piecewise-linear gain over the loop, by bar: [(bar, gain), ...]. Should end where it starts."""
    bars = np.arange(N + TAIL) / SR / BAR
    b, g = zip(*points)
    return np.interp(bars, b, g)


def add(buf, start_s, sound):
    i = int(round(start_s * SR))
    j = min(i + len(sound), len(buf))
    buf[i:j] += sound[: j - i]


def pan(mono, position):
    """Equal-power pan, position -1 (left) to 1 (right)."""
    a = (position + 1.0) * np.pi / 4.0
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def drone():
    t = seconds(N + TAIL)
    root = loop_hz(midi_hz(28))  # E1
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * t * 3 / LENGTH)
    growl_lfo = 0.5 + 0.5 * np.sin(2 * np.pi * t * 4 / LENGTH + 1.0)
    out = np.zeros((len(t), 2))
    for detune, side in [(1.0, -0.4), (loop_hz(root * 1.004) / root, 0.4)]:
        f = root * detune
        tone = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2 * f * t)
        # A few upper harmonics fade in and out with the slow LFO, like a filter breathing.
        for h in range(3, 9):
            tone += (0.35 / h) * growl_lfo * np.sin(2 * np.pi * h * f * t + h)
        out += pan(tone * swell, side)
    fifth = loop_hz(midi_hz(35))  # B1
    out += pan(0.3 * np.sin(2 * np.pi * fifth * t) * (1 - swell * 0.5), 0.0)
    return out * 0.12


def pad_note(note, duration, rng, attack=2.5, release=3.5):
    n = int((duration + release) * SR)
    t = seconds(n)
    voice = np.zeros(n)
    base = midi_hz(note)
    for cents in (-9, 0, 8):
        f = base * 2 ** (cents / 1200)
        phase = rng.uniform(0, 2 * np.pi)
        for h in range(1, 40):
            if h * f > 3500:
                break
            voice += np.sin(2 * np.pi * h * f * t + phase * h) * (1 / h) * np.exp(-h * f / 900)
    shape = np.clip(t / attack, 0, 1) * np.clip((duration + release - t) / release, 0, 1)
    shimmer = 1 + 0.15 * np.sin(2 * np.pi * rng.uniform(0.1, 0.25) * t + rng.uniform(0, 6))
    return voice * shape ** 2 * shimmer


def pads(rng):
    out = np.zeros((N + TAIL, 2))
    for i, chord in enumerate(CHORDS):
        start = i * 4 * BAR
        for k, note in enumerate(chord):
            tone = pad_note(note, 4 * BAR, rng)
            add_stereo(out, start, pan(tone, [-0.6, 0.6, -0.25, 0.25][k]))
    return out * 0.045


def add_stereo(buf, start_s, sound):
    i = int(round(start_s * SR))
    j = min(i + len(sound), len(buf))
    buf[i:j] += sound[: j - i]


def sub_pulse():
    """Eighth-note sub bass on each chord's root, pumping like a slow heartbeat underneath."""
    out = np.zeros(N + TAIL)
    n = int(0.36 * SR)
    for step in range(BARS * 8):
        start = step * BEAT / 2
        root = CHORDS[int(start // (4 * BAR)) % len(CHORDS)][0] - 12
        accent = 1.0 if step % 2 == 0 else 0.55
        f = midi_hz(root)
        tone = np.sin(2 * np.pi * f * seconds(n)) * env(n, 0.012, 0.13) * accent
        add(out, start, tone)
    out *= gain_curve([(0, 0.15), (4, 0.25), (8, 0.8), (20, 1.0), (22, 0.5), (24, 0.15)])
    return pan(out * 0.45, 0.0)


def heartbeat(rng):
    """A low lub-dub thump on the first beat of each bar once the tension builds."""
    out = np.zeros(N + TAIL)
    n = int(0.4 * SR)
    for bar in range(BARS):
        for offset, level in ((0.0, 1.0), (0.28, 0.6)):
            thump = sine_sweep(n, [(0, 85), (0.08, 45), (1, 40)]) * env(n, 0.004, 0.1) * level
            add(out, bar * BAR + offset, thump)
    out *= gain_curve([(0, 0), (7, 0), (9, 0.8), (20, 1.0), (22, 0.3), (23, 0), (24, 0)])
    return pan(out * 0.8, 0.0)


def ticks(rng):
    """Metallic sixteenth-note ticks, like insect legs on hot metal. They join once the beat has."""
    out = np.zeros((N + TAIL, 2))
    n = int(0.09 * SR)
    t = seconds(n)
    pattern = [1.0, 0.25, 0.5, 0.3, 0.8, 0.25, 0.45, 0.6, 1.0, 0.3, 0.5, 0.25, 0.75, 0.4, 0.3, 0.55]
    for step in range(BARS * 16):
        level = pattern[step % 16] * rng.uniform(0.7, 1.0)
        ring = sum(np.sin(2 * np.pi * f * rng.uniform(0.98, 1.02) * t) for f in (3150, 4730, 6410, 8890))
        click = (ring * 0.25 + rng.uniform(-1, 1, n)) * np.exp(-t / 0.012) * level
        add_stereo(out, step * BEAT / 4, pan(click, 0.5 * np.sin(step * 0.7)))
    out = fft_filter(out, low_hz=2500)
    out *= gain_curve([(0, 0), (11, 0), (13, 0.5), (17, 1.0), (21, 1.0), (22, 0.2), (23, 0), (24, 0)])[:, None]
    return out * 0.5


def bell(note, rng):
    """Glassy FM blip with an inharmonic ratio, so it sounds alien rather than like a real bell."""
    n = int(1.8 * SR)
    t = seconds(n)
    f = midi_hz(note)
    index = 2.5 * np.exp(-t / 0.25)
    tone = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * 3.53 * t))
    return tone * env(n, 0.002, 0.45)


def bells(rng):
    out = np.zeros((N + TAIL, 2))
    for step in range(BARS * 8):
        if rng.uniform() < 0.16:
            note = rng.choice(SCALE) + rng.choice([24, 36])
            add_stereo(out, step * BEAT / 2, pan(bell(note, rng) * rng.uniform(0.4, 1.0), rng.uniform(-0.8, 0.8)))
    # Ping-pong echo on a dotted eighth.
    delay = int(0.75 * BEAT * SR)
    echoed = out.copy()
    tap = out
    for i in range(1, 5):
        tap = np.roll(tap[:, ::-1], delay, axis=0) * 0.45
        echoed += tap
    return echoed * 0.2


def lead():
    """A theremin-like voice that sings a slow phrygian line over the middle of the loop."""
    melody = [  # (bar, beat, midi note, beats held)
        (12, 0, 64, 6), (13, 2, 65, 2), (14, 0, 67, 3), (14, 3, 65, 1), (15, 0, 64, 4),
        (16, 0, 70, 4), (17, 0, 69, 2), (17, 2, 65, 2), (18, 0, 64, 4),
        (19, 0, 62, 2), (19, 2, 65, 2), (20, 0, 64, 7),
    ]
    total = N + TAIL
    pitch = np.full(total, np.nan)
    amp = np.zeros(total)
    for bar, beat, note, hold in melody:
        i = int((bar * BAR + beat * BEAT) * SR)
        j = int((bar * BAR + (beat + hold) * BEAT) * SR)
        pitch[i:j] = note
        amp[i:j] = 1.0
    # Hold the last pitch through rests, then glide between notes.
    idx = np.where(np.isnan(pitch), 0, np.arange(total))
    np.maximum.accumulate(idx, out=idx)
    pitch = np.nan_to_num(pitch[idx], nan=64.0)
    k = 1.0 - np.exp(-1.0 / (0.09 * SR))
    smooth = np.empty(total)
    smooth_amp = np.empty(total)
    p, a = pitch[0], 0.0
    ka = 1.0 - np.exp(-1.0 / (0.25 * SR))
    for i in range(total):
        p += (pitch[i] - p) * k
        a += (amp[i] - a) * ka
        smooth[i], smooth_amp[i] = p, a
    t = seconds(total)
    vibrato = 0.18 * np.sin(2 * np.pi * 5.3 * t) * smooth_amp
    freq = 440.0 * 2.0 ** ((smooth + vibrato - 69) / 12.0)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = (np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.06 * np.sin(3 * phase)) * smooth_amp
    return pan(tone * 0.12, 0.15)


def reverb(x, rng, decay=2.2, length=4.0):
    """Circular convolution with decaying noise, so the reverb tail wraps across the loop point."""
    n = int(length * SR)
    t = seconds(n)
    ir = rng.normal(0, 1, (n, 2)) * np.exp(-t / (decay / 6.9))[:, None]
    ir = fft_filter(ir, high_hz=4500)
    ir /= np.sqrt(np.sum(ir ** 2, axis=0))
    padded = np.zeros_like(x)
    padded[:n] = ir
    return np.fft.irfft(np.fft.rfft(x, axis=0) * np.fft.rfft(padded, axis=0), n=x.shape[0], axis=0)


def fold(x):
    """Wraps everything that rang past the end back onto the start, then trims to one loop."""
    out = x[:N].copy()
    out[: x.shape[0] - N] += x[N:]
    return out


def music(rng):
    metal = ticks(rng)
    wet = fold(pads(rng) + bells(rng) + lead() + metal * 0.5)
    dry = fold(drone() + sub_pulse() + heartbeat(rng) + metal * 0.5)
    mix = dry + wet * 0.55 + reverb(wet, rng) * 0.9 + reverb(dry, rng) * 0.12
    mix = fft_filter(mix, low_hz=28)  # No DC or rumble below the low E.
    mix = np.tanh(mix / np.max(np.abs(mix)) * 1.3)  # Gentle saturation glues it together.
    return normalize(mix, -1.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)
    for name, make in [
        ("player_attack", player_attack),
        ("enemy_hit", enemy_hit),
        ("player_hit", player_hit),
        ("enemy_attack", enemy_attack),
    ]:
        write_wav(os.path.join(OUT, name + ".wav"), make(rng))
        print("wrote", name + ".wav")

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "music.wav")
        write_wav(wav_path, music(rng))
        ogg_path = os.path.join(OUT, "alien_swarm_theme.ogg")
        subprocess.run(
            # Quality 5: lower settings smear the last samples enough to click at the loop point.
            ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", ogg_path],
            check=True,
        )
    print("wrote alien_swarm_theme.ogg")


if __name__ == "__main__":
    main()

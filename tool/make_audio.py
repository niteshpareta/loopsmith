#!/usr/bin/env python3
"""Builds every sound in assets/audio.

Short physical sounds (ring ticks, knocks, button taps) are recordings from
Kenney's Interface Sounds pack (CC0, www.kenney.nl), kept in tool/cc0. Pitched
sounds and the music are synthesised here so they all share one key.

    pip install numpy scipy lameenc
    python3 tool/make_audio.py

All pitched sounds sit in C major pentatonic (C D E G A) so effects always
agree with the music. Replace any file with a recorded one of the same name
and the game will use it; keep the three music loops the same length or update
the loop lengths in lib/services/audio.dart.
"""
import os
import wave

import lameenc
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(11)

C4, D4, E4, G4, A4 = 261.63, 293.66, 329.63, 392.00, 440.00
C5, D5, E5, G5, A5 = 523.25, 587.33, 659.25, 783.99, 880.00
C6, D6, E6, G6, A6, C7 = 1046.5, 1174.66, 1318.51, 1567.98, 1760.0, 2093.0


# ---------------------------------------------------------------- helpers
def tt(d):
    return np.arange(int(SR * d)) / SR


def decay(d, tau, attack=0.003):
    x = tt(d)
    return (1 - np.exp(-x / attack)) * np.exp(-x / tau)


def lowpass(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="low", fs=SR, output="sos"), x, axis=0)


def highpass(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x, axis=0)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x, axis=0)


def noise(d):
    return rng.standard_normal(int(SR * d))


def fade_out(x, d=0.02):
    n = min(len(x), int(SR * d))
    y = x.copy()
    y[-n:] = (y[-n:].T * np.linspace(1, 0, n)).T
    return y


def mix(buf, clip, at, gain=1.0):
    """Adds clip into buf starting at `at` seconds, growing buf if needed."""
    i = int(SR * at)
    need = i + len(clip)
    if need > len(buf):
        pad = np.zeros((need - len(buf),) + buf.shape[1:])
        buf = np.concatenate([buf, pad])
    buf[i:need] += clip * gain
    return buf


def stereo(x, pan=0.0):
    """Equal-power pan, -1 left to 1 right."""
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def reverb_ir(seconds=2.2, tone=3200.0, seed=3):
    r = np.random.default_rng(seed)
    n = int(SR * seconds)
    x = np.arange(n) / SR
    out = []
    for ch in range(2):
        ir = r.standard_normal(n) * np.exp(-x / (seconds / 6.0))
        ir[: int(SR * 0.012)] *= np.linspace(0, 1, int(SR * 0.012))  # pre-delay
        ir = lowpass(ir, tone)
        out.append(ir / np.sqrt(np.sum(ir**2)))
    return np.stack(out, axis=1)


def reverb(x, wet=0.25, seconds=2.2, tone=3200.0):
    """Returns stereo. Tail is appended."""
    if x.ndim == 1:
        x = stereo(x)
    ir = reverb_ir(seconds, tone)
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    out = np.zeros((n, 2))
    for ch in range(2):
        out[:, ch] = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(ir[:, ch], size), size)[:n]
    dry = np.zeros((n, 2))
    dry[: len(x)] = x
    return dry + out * wet


def reverb_loop(x, wet=0.3, seconds=3.5, tone=2800.0):
    """Circular reverb: the tail wraps round, so a loop stays seamless."""
    ir = reverb_ir(seconds, tone)
    n = len(x)
    out = np.zeros_like(x)
    for ch in range(2):
        padded = np.zeros(n)
        m = min(n, len(ir))
        padded[:m] = ir[:m, ch]
        out[:, ch] = np.fft.irfft(np.fft.rfft(x[:, ch]) * np.fft.rfft(padded), n)
    return x + out * wet


def mix_loop(buf, clip, at):
    """Adds a stereo clip into a loop buffer, wrapping past the end."""
    n = len(buf)
    idx = (int(SR * at) + np.arange(len(clip))) % n
    np.add.at(buf, idx, clip)


def normalise(x, peak_db):
    peak = np.max(np.abs(x))
    return x if peak == 0 else x * (10 ** (peak_db / 20) / peak)


def trim_tail(x, floor_db=-62.0):
    """Cuts the inaudible end of a reverb tail to keep files small."""
    level = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    loud = np.nonzero(level > np.max(level) * 10 ** (floor_db / 20))[0]
    return x if len(loud) == 0 else x[: min(len(x), loud[-1] + int(SR * 0.03))]


def write_wav(name, x, peak_db=-6.0):
    x = fade_out(trim_tail(normalise(x, peak_db)), 0.02)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    path = os.path.join(OUT, "sfx", name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"sfx/{name:14s} {len(x) / SR:5.2f}s  {os.path.getsize(path) / 1024:6.0f} KB")


LOOP_MARGIN = 0.5  # seconds of wrapped audio before and after the loop


def write_loop(name, loop, peak_db=-7.0, bitrate=128):
    """Writes an MP3 as [end of loop][loop][start of loop].

    MP3 encoders add a little silence at the start of a file, which would
    click on every repeat. With wrapped margins the player can loop any
    window exactly one loop long and land on continuous audio.
    """
    loop = normalise(loop, peak_db)
    m = int(SR * LOOP_MARGIN)
    full = np.concatenate([loop[-m:], loop, loop[:m]])
    pcm = (np.clip(full, -1, 1) * 32767).astype("<i2")
    enc = lameenc.Encoder()
    enc.set_bit_rate(bitrate)
    enc.set_in_sample_rate(SR)
    enc.set_channels(2)
    enc.set_quality(2)
    enc.silence()
    data = enc.encode(pcm.tobytes()) + enc.flush()
    path = os.path.join(OUT, "music", name)
    with open(path, "wb") as f:
        f.write(data)
    print(f"music/{name:13s} loop {len(loop) / SR:5.1f}s  {os.path.getsize(path) / 1024:6.0f} KB")


# ---------------------------------------------------------------- voices
def bell(f, d=0.9, bright=1.0):
    """Small brass bell: slightly inharmonic partials, quick shimmer."""
    x = tt(d)
    parts = [(1.0, 1.0, 0.36), (2.0, 0.42, 0.24), (2.76, 0.22 * bright, 0.16),
             (4.07, 0.12 * bright, 0.10), (5.4, 0.07 * bright, 0.07)]
    out = np.zeros(len(x))
    for ratio, amp, tau in parts:
        out += amp * np.sin(2 * np.pi * f * ratio * x) * np.exp(-x / (tau * d * 1.6))
    out += 0.25 * np.sin(2 * np.pi * f * 1.004 * x) * np.exp(-x / (0.4 * d))
    return out * (1 - np.exp(-x / 0.002))


def mallet(f, d=1.6):
    """Soft wooden mallet on a tuned bar."""
    x = tt(d)
    out = np.sin(2 * np.pi * f * x) * np.exp(-x / 0.55)
    out += 0.28 * np.sin(2 * np.pi * f * 4.0 * x) * np.exp(-x / 0.07)
    out += 0.10 * np.sin(2 * np.pi * f * 2.0 * x) * np.exp(-x / 0.3)
    thump = lowpass(noise(d), 900) * np.exp(-x / 0.012) * 0.5
    return (out + thump) * (1 - np.exp(-x / 0.004))


def glass(f, d=2.4):
    x = tt(d)
    trem = 1 + 0.18 * np.sin(2 * np.pi * 4.3 * x)
    out = np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * f * 2.01 * x) * np.exp(-x / 0.4)
    return out * trem * np.exp(-x / 0.8) * (1 - np.exp(-x / 0.03))


def metal_tick(seed):
    """A ring turning one notch against another."""
    r = np.random.default_rng(seed)
    d = 0.11
    x = tt(d)
    click = highpass(r.standard_normal(len(x)), 2500) * np.exp(-x / 0.0025)
    ping = np.zeros(len(x))
    for f, amp, tau in [(2150, 0.5, 0.022), (3420, 0.35, 0.016), (5230, 0.2, 0.010)]:
        ping += amp * np.sin(2 * np.pi * f * (1 + r.uniform(-0.03, 0.03)) * x) * np.exp(-x / tau)
    body = 0.7 * np.sin(2 * np.pi * (190 - 400 * x) * x) * np.exp(-x / 0.03)
    return click * 0.5 + ping * 0.6 + body


# ---------------------------------------------------------------- recordings
CC0 = os.path.join(os.path.dirname(__file__), "cc0", "kenney_interface")

# output name: (recording, peak in dBFS, pitch ratio)
RECORDED = {
    "turn_1.wav": ("tick_001.wav", -9, 1.0),
    "turn_2.wav": ("tick_002.wav", -9, 1.0),
    "turn_3.wav": ("click_005.wav", -10, 1.0),
    # drop_003 rings at about 739 Hz; nudged up to G5 so it sits in key.
    "peg.wav": ("drop_003.wav", -8, 783.99 / 739.0),
    "tray.wav": ("drop_002.wav", -7, 0.9),
    "tap.wav": ("select_002.wav", -13, 1.0),
    "blocked.wav": ("back_002.wav", -11, 0.85),
    "undo.wav": ("back_004.wav", -12, 1.0),
}


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2 and w.getframerate() == SR, path
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(axis=1)
    return x


def repitch(x, ratio):
    """Plays a sound faster (ratio > 1) or slower, like a tape."""
    if ratio == 1.0:
        return x
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


def import_recorded():
    for name, (source, peak_db, ratio) in RECORDED.items():
        x = repitch(read_wav(os.path.join(CC0, source)), ratio)
        write_wav(name, x, peak_db)


# ---------------------------------------------------------------- effects
def make_sfx():
    for i in range(3):
        write_wav(f"turn_{i + 1}.wav", metal_tick(20 + i), -11)

    # Opening meets a link: one soft bell.
    write_wav("align.wav", reverb(bell(A5, 0.7, 0.6) * 0.8, 0.18, 1.2), -12)

    # Ring freed: a rising fifth. The game pitches it up for each ring in a row.
    x = np.zeros(1)
    x = mix(x, bell(C5, 0.55), 0.0, 0.8)
    x = mix(x, bell(G5, 0.9), 0.085, 1.0)
    write_wav("free.wav", reverb(x, 0.22, 1.6), -7)

    # Ring lands on a peg: wooden knock.
    d = 0.16
    t = tt(d)
    knock = np.sin(2 * np.pi * 330 * t) * np.exp(-t / 0.028) + 0.5 * np.sin(2 * np.pi * 668 * t) * np.exp(-t / 0.016)
    knock += bandpass(noise(d), 800, 3000) * np.exp(-t / 0.004) * 0.6
    write_wav("peg.wav", knock, -9)

    # Ring drops into the tray: felt thump.
    d = 0.24
    t = tt(d)
    thump = np.sin(2 * np.pi * (118 - 150 * t) * t) * np.exp(-t / 0.06)
    thump += lowpass(noise(d), 500) * np.exp(-t / 0.02) * 0.8
    write_wav("tray.wav", thump, -8)

    # Level clear: four rising notes that resolve on C.
    x = np.zeros(1)
    for i, f in enumerate([C5, E5, G5, C6]):
        x = mix(x, mallet(f, 1.4), i * 0.115, 0.8)
        x = mix(x, bell(f, 1.2, 0.7), i * 0.115, 0.5)
    for f in [C5, E5, G5]:
        x = mix(x, bell(f * 2, 1.6, 0.4), 0.48, 0.18)
    write_wav("win.wav", reverb(x, 0.3, 2.4), -6)

    # Tap on a ring that cannot turn: dull, never a buzzer.
    d = 0.09
    t = tt(d)
    dull = lowpass(noise(d), 700) * np.exp(-t / 0.012) + 0.6 * np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.02)
    write_wav("blocked.wav", dull, -12)

    # Button tap.
    d = 0.06
    t = tt(d)
    tap = np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.012) + highpass(noise(d), 4000) * np.exp(-t / 0.002) * 0.25
    write_wav("tap.wav", tap, -14)

    # Coin.
    x = np.zeros(1)
    x = mix(x, bell(E6, 0.25, 1.2), 0.0, 0.8)
    x = mix(x, bell(A6, 0.4, 1.2), 0.05, 1.0)
    write_wav("coin.wav", x, -11)

    # Star: one bright note. Pitched up for the second and third star.
    write_wav("star.wav", reverb(bell(G5, 0.7, 1.1) + 0.5 * mallet(G5, 0.7), 0.2, 1.2), -8)

    # Tray full: two soft falling notes, muffled.
    x = np.zeros(1)
    x = mix(x, mallet(E4, 1.0), 0.0)
    x = mix(x, mallet(C4, 1.4), 0.22)
    write_wav("fail.wav", reverb(lowpass(x, 1400), 0.25, 1.8), -9)

    # Hint: three quick sparkles.
    x = np.zeros(1)
    for i, f in enumerate([C6, E6, G6]):
        x = mix(x, glass(f, 0.5), i * 0.06, 0.7)
    write_wav("hint.wav", reverb(x, 0.3, 1.4), -11)

    # Undo: a short breath in reverse.
    d = 0.22
    t = tt(d)
    swell = bandpass(noise(d), 500, 3500) * (t / d) ** 2
    swell += 0.4 * np.sin(2 * np.pi * (300 + 500 * t / d) * t) * (t / d)
    write_wav("undo.wav", fade_out(swell, 0.03), -13)

    # A sealed ring opens: snap, then a rising sparkle.
    x = np.zeros(1)
    snap = highpass(noise(0.05), 1800) * np.exp(-tt(0.05) / 0.006)
    x = mix(x, snap, 0.0, 0.9)
    for i, f in enumerate([E5, A5, D6]):
        x = mix(x, bell(f, 0.5, 1.0), 0.03 + i * 0.05, 0.6)
    write_wav("unseal.wav", reverb(x, 0.2, 1.3), -9)

    # New skin unlocked: a small fanfare.
    x = np.zeros(1)
    for i, f in enumerate([C5, G5, C6, E6, G6]):
        x = mix(x, bell(f, 1.5, 0.9), i * 0.09, 0.7)
        x = mix(x, mallet(f, 1.2), i * 0.09, 0.4)
    x = mix(x, bell(C7, 1.8, 0.5), 0.5, 0.25)
    write_wav("unlock.wav", reverb(x, 0.32, 2.6), -6)


# ---------------------------------------------------------------- music
def pad_note(f, d, seed):
    r = np.random.default_rng(seed)
    x = tt(d)
    out = np.zeros(len(x))
    for det, amp in [(1.0, 1.0), (1.0035, 0.55), (0.9968, 0.5)]:
        out += amp * np.sin(2 * np.pi * f * det * x + r.uniform(0, 6.28))
    out += 0.16 * np.sin(2 * np.pi * f * 2 * x + r.uniform(0, 6.28))
    out += 0.05 * np.sin(2 * np.pi * f * 3 * x + r.uniform(0, 6.28))
    swell = 1 + 0.22 * np.sin(2 * np.pi * x / r.uniform(5.0, 9.0) + r.uniform(0, 6.28))
    return out * swell


def make_pad():
    """32 s of slow warm chords: Am11, Fmaj9, Cadd9, Gsus2."""
    bar, cross = 8.0, 2.5
    chords = [
        [110.00, 164.81, 196.00, 261.63, 293.66],
        [87.31, 130.81, 220.00, 329.63, 392.00],
        [130.81, 196.00, 293.66, 329.63],
        [98.00, 146.83, 220.00, 329.63],
    ]
    length = bar * len(chords)
    loop = np.zeros((int(SR * length), 2))
    d = bar + 2 * cross
    x = tt(d)
    window = np.ones(len(x))
    n = int(SR * cross * 2)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))
    window[:n] = ramp
    window[-n:] = ramp[::-1]
    for ci, chord in enumerate(chords):
        for ni, f in enumerate(chord):
            gain = 1.0 / (1 + 0.55 * ni)  # roll off the upper notes
            note = pad_note(f, d, 100 + ci * 10 + ni) * window * gain
            pan = np.sin(2 * np.pi * x / 11.0 + ni * 1.7 + ci) * 0.45
            a = (pan + 1) * np.pi / 4
            clip = np.stack([note * np.cos(a), note * np.sin(a)], axis=1)
            mix_loop(loop, clip, ci * bar - cross)
    loop = lowpass(loop, 1800)
    air = lowpass(highpass(rng.standard_normal(loop.shape), 3000), 7000) * 0.004
    loop = reverb_loop(loop + air, 0.35, 4.0, 2400)
    write_loop("pad.mp3", loop, -9)
    return length


def make_mallets():
    """24 s of sparse mallet phrases, free of any fixed beat."""
    length = 24.0
    loop = np.zeros((int(SR * length), 2))
    phrases = [
        (0.4, E4, 0.9, -0.3), (1.05, G4, 0.8, 0.2), (1.95, A4, 1.0, 0.4),
        (6.2, D5, 0.7, -0.4), (7.1, C5, 0.85, -0.1), (7.75, A4, 0.6, 0.3),
        (11.6, G4, 0.9, 0.35), (12.15, A4, 0.75, 0.1), (13.2, C5, 1.0, -0.25), (14.6, E5, 0.6, -0.45),
        (18.4, E4, 0.8, 0.15), (19.6, D4, 0.9, -0.2), (21.0, C4, 1.0, 0.0),
    ]
    for at, f, vel, pan in phrases:
        mix_loop(loop, stereo(mallet(f, 2.2) * vel, pan), at)
        mix_loop(loop, stereo(mallet(f * 2, 1.0) * vel * 0.12, -pan), at + 0.01)
    loop = reverb_loop(loop, 0.4, 3.5, 3000)
    write_loop("mallets.mp3", loop, -8)
    return length


def make_shimmer():
    """20 s of high glassy notes for the last rings of a level."""
    length = 20.0
    loop = np.zeros((int(SR * length), 2))
    notes = [
        (0.8, G6, 0.8, 0.5), (3.9, E6, 1.0, -0.4), (7.2, A6, 0.7, 0.2), (7.85, C7, 0.5, -0.2),
        (11.5, D6, 0.9, -0.5), (14.8, G6, 0.8, 0.4), (16.6, E6, 0.9, 0.0), (18.7, C6, 0.7, 0.3),
    ]
    for at, f, vel, pan in notes:
        mix_loop(loop, stereo(glass(f, 2.8) * vel, pan), at)
    loop = reverb_loop(loop, 0.6, 4.5, 5000)
    write_loop("shimmer.mp3", loop, -10)
    return length


if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
    make_sfx()
    import_recorded()  # replaces the synthesised ticks, knocks and taps
    lengths = [make_pad(), make_mallets(), make_shimmer()]
    print("loop lengths (seconds):", lengths, "margin:", LOOP_MARGIN)

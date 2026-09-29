"""Генератор временных звуков и музыки: процедурный синтез в духе 8/16-бит.

    python tools/generate_audio.py                  # всё: assets/audio/sfx/*.ogg и assets/audio/music/*.ogg
    python tools/generate_audio.py sfx              # только эффекты
    python tools/generate_audio.py music            # только музыка
    python tools/generate_audio.py click forest     # только эти файлы (имена без .ogg)
    python tools/generate_audio.py --keep           # не трогать уже существующие файлы (например, заменённые на свои)

Нужны numpy, scipy и soundfile: pip install numpy scipy soundfile.
Любой файл можно заменить своим (OGG с тем же именем) — список и назначение: assets/audio/README.md.
Результат детерминирован: у каждого звука и трека свой seed.
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
SR = 32000
rng = np.random.default_rng(1)


# --- Базовые блоки ----------------------------------------------------------------------

class Sig(np.ndarray):
    """Моно-сигнал: при сложении более короткий дополняется тишиной (звуки разной длины можно просто складывать)."""

    def __new__(cls, data):
        return np.asarray(data, float).view(cls)

    def __add__(self, other):
        if isinstance(other, np.ndarray) and other.ndim == 1 and len(other) != len(self):
            out = np.zeros(max(len(self), len(other)))
            out[:len(self)] += np.asarray(self)
            out[:len(other)] += np.asarray(other)
            return Sig(out)
        return np.ndarray.__add__(self, other)

    __radd__ = __add__


def n_of(dur):
    return max(1, int(round(dur * SR)))


def times(dur):
    return np.arange(n_of(dur)) / SR


def freq_line(f0, f1, dur, exp=True):
    """Частота, плавно меняющаяся от f0 до f1 (экспоненциально — «на слух» ровно)."""
    x = np.linspace(0.0, 1.0, n_of(dur))
    return f0 * (f1 / f0) ** x if exp else f0 + (f1 - f0) * x


def _blep(t, dt):
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def osc(kind, freq, dur, duty=0.5):
    """Генератор: sine, tri, saw, square (без лишнего «звона» — polyBLEP), noise."""
    n = n_of(dur)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.resize(np.asarray(freq, float), n)
    if kind == "noise":
        return Sig(rng.uniform(-1.0, 1.0, n))
    ph = np.cumsum(f) / SR
    frac = ph % 1.0
    dt = np.clip(f / SR, 1e-6, 0.5)
    if kind == "sine":
        return Sig(np.sin(2 * np.pi * ph))
    if kind == "tri":
        return Sig(4.0 * np.abs(frac - 0.5) - 1.0)
    if kind == "saw":
        return Sig(2.0 * frac - 1.0 - _blep(frac, dt))
    if kind == "square":
        return Sig(np.where(frac < duty, 1.0, -1.0) + _blep(frac, dt) - _blep((frac - duty) % 1.0, dt))
    raise ValueError(kind)


def env(dur, attack=0.004, decay=None, release=0.02, sustain=1.0):
    """Огибающая: атака, затем экспоненциальный спад (decay — постоянная времени) или удержание, в конце — затухание."""
    n = n_of(dur)
    t = np.arange(n) / SR
    e = np.ones(n) * sustain
    if decay:
        e = np.exp(-np.maximum(t - attack, 0.0) / decay) * (1.0 - sustain) + sustain
    a = max(1, n_of(attack))
    e[:a] *= np.linspace(0.0, 1.0, a)
    r = min(n, n_of(release))
    e[n - r:] *= np.linspace(1.0, 0.0, r)
    return Sig(e)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return Sig(signal.lfilter(b, a, x))


def hp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "high")
    return Sig(signal.lfilter(b, a, x))


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return Sig(signal.lfilter(b, a, x))


def svf(x, cutoff, q=1.0, mode="bp"):
    """Фильтр с меняющейся частотой среза (свисты, взмахи). cutoff — массив той же длины."""
    cutoff = np.resize(np.asarray(cutoff, float), len(x))
    f = 2.0 * np.sin(np.pi * np.minimum(cutoff, SR / 6.5) / SR)
    damp = 1.0 / q
    low = band = 0.0
    out = np.zeros_like(x)
    for i in range(len(x)):
        high = x[i] - low - damp * band
        band += f[i] * high
        low += f[i] * band
        out[i] = band if mode == "bp" else (low if mode == "lp" else high)
    return Sig(out)


def pluck_ks(freq, dur, decay=0.995):
    """Щипок струны (Карплус — Стронг): тетива лука, арфа."""
    n = n_of(dur)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1.0, 1.0, period)
    out = np.zeros(n)
    for i in range(n):
        k = i % period
        out[i] = buf[k]
        buf[k] = decay * 0.5 * (buf[k] + buf[(k + 1) % period])
    return Sig(out)


def place(parts, total=None):
    """Смешать (сдвиг в секундах, звук) в одну дорожку."""
    end = max(n_of(off) + len(x) for off, x in parts)
    out = np.zeros(max(end, n_of(total) if total else 0))
    for off, x in parts:
        s = n_of(off) if off > 0 else 0
        out[s:s + len(x)] += x
    return Sig(out)


def reverb(x, secs=1.2, wet=0.25, damp=5000.0, seed=3, wrap=None):
    """Реверберация сверткой с синтетическим «хвостом». wrap — длина петли: хвост переносится в её начало."""
    local = np.random.default_rng(seed)
    n = n_of(secs)
    t = np.arange(n) / SR
    ir = local.normal(0.0, 1.0, n) * np.exp(-t * 6.9 / secs)
    ir = lp(ir, damp)
    ir[:n_of(0.012)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet_sig = signal.fftconvolve(x, ir)
    out = np.concatenate([x, np.zeros(len(wet_sig) - len(x))]) + wet * wet_sig
    if wrap:
        loop = np.zeros(wrap)
        for start in range(0, len(out), wrap):
            chunk = out[start:start + wrap]
            loop[:len(chunk)] += chunk
        return Sig(loop)
    return Sig(out)


def tone(freq, dur, kind="square", attack=0.003, decay=None, release=0.02, duty=0.5, vib=0.0, vib_rate=6.0, cutoff=None, sustain=0.0):
    f = np.full(n_of(dur), float(freq)) if np.isscalar(freq) else np.asarray(freq, float)
    if vib:
        f = f * (1.0 + vib * np.sin(2 * np.pi * vib_rate * np.arange(len(f)) / SR))
    x = osc(kind, f, dur, duty) * env(dur, attack, decay, release, sustain if decay else 1.0)
    return lp(x, cutoff) if cutoff else x


def bell(freq, dur, decay=0.5, bright=1.0):
    """Колокольчик/металл: негармонические обертоны с разным затуханием."""
    parts = [(1.0, 1.0, 1.0), (2.76, 0.5 * bright, 0.6), (5.4, 0.25 * bright, 0.35), (8.93, 0.12 * bright, 0.2)]
    out = np.zeros(n_of(dur))
    for ratio, amp, dec in parts:
        if freq * ratio < SR * 0.45:
            out += amp * tone(freq * ratio, dur, "sine", 0.002, decay * dec, 0.02)
    return Sig(out)


def noise_burst(dur, lo=None, hi=None, decay=0.05, attack=0.002):
    x = osc("noise", 0, dur)
    if lo and hi:
        x = bp(x, lo, hi)
    elif hi:
        x = lp(x, hi)
    elif lo:
        x = hp(x, lo)
    return x * env(dur, attack, decay, 0.01)


def whoosh(dur, f0, f1, q=2.0, attack=0.3):
    """Взмах: шум через полосовой фильтр, частота которого едет от f0 к f1."""
    x = svf(osc("noise", 0, dur), freq_line(f0, f1, dur), q, "bp")
    n = n_of(dur)
    shape = np.sin(np.pi * np.clip(np.linspace(0.0, 1.0, n) / (2 * attack), 0.0, 0.5)) ** 2
    shape *= np.linspace(1.0, 0.0, n) ** 1.5
    return x * shape


def coin(pitch=1.0, dur=0.16):
    a = tone(1975 * pitch, 0.05, "square", 0.001, 0.03, 0.005, duty=0.25)
    b = tone(2637 * pitch, dur - 0.045, "square", 0.001, 0.05, 0.02, duty=0.25)
    return lp(place([(0.0, a), (0.045, b)]), 7000)


def thud(f0=150, f1=55, dur=0.12, noise=0.5, noise_hi=1800):
    body = tone(freq_line(f0, f1, dur), dur, "sine", 0.001, dur * 0.35, 0.01)
    return body + noise * noise_burst(dur, hi=noise_hi, decay=0.02)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def finish(x, peak=0.8):
    x = np.asarray(x, float)
    x = hp(x, 25, 1)
    level = np.abs(x)
    above = np.nonzero(level > level.max() * 0.001)[0]
    if len(above):
        x = x[:min(len(x), above[-1] + n_of(0.01))]
    fade = min(len(x), n_of(0.006))
    x[len(x) - fade:] *= np.linspace(1.0, 0.0, fade)
    return x / (np.max(np.abs(x)) + 1e-9) * peak


# --- Эффекты ----------------------------------------------------------------------------
# Каждый — функция без аргументов, возвращает моно-сигнал. Громкость между звуками выравнивает игра
# (Sound.SOUNDS), здесь все нормированы по пику.

SFX = {}


def sfx(fn):
    SFX[fn.__name__] = fn
    return fn


# Интерфейс

@sfx
def click():
    return tone(2100, 0.035, "sine", 0.0005, 0.008, 0.005) + 0.25 * noise_burst(0.02, lo=3000, decay=0.004)


@sfx
def tab():
    return tone(1480, 0.05, "tri", 0.0005, 0.012, 0.005) + 0.4 * tone(2960, 0.03, "sine", 0.0005, 0.006, 0.005)


@sfx
def panel_open():
    return whoosh(0.16, 500, 2600, 1.5, 0.5) + 0.25 * tone(freq_line(620, 930, 0.1), 0.1, "sine", 0.01, 0.04, 0.02)


@sfx
def panel_close():
    return whoosh(0.14, 2400, 450, 1.5, 0.3) + 0.2 * tone(freq_line(900, 600, 0.08), 0.08, "sine", 0.005, 0.03, 0.02)


@sfx
def equip():
    metal = bell(640, 0.3, 0.12, 1.2) + 0.6 * bell(1010, 0.25, 0.08)
    return metal + 0.6 * noise_burst(0.05, lo=2000, decay=0.012)


@sfx
def sell():
    return place([(0.0, coin(1.0)), (0.06, 0.8 * coin(1.06)), (0.12, 0.7 * coin(0.95)), (0.2, 0.6 * coin(1.12))])


@sfx
def upgrade_ok():
    anvil = bell(880, 0.6, 0.35, 1.3)
    sparkle = place([(0.08 + i * 0.06, 0.35 * tone(f, 0.25, "tri", 0.002, 0.08, 0.05)) for i, f in enumerate([1318, 1760, 2637])])
    return reverb(place([(0.0, anvil), (0.0, sparkle)]), 0.8, 0.2)


@sfx
def upgrade_fail():
    clunk = thud(160, 70, 0.18, 0.8, 1200)
    sad = tone(freq_line(330, 150, 0.35), 0.35, "square", 0.005, 0.2, 0.05, duty=0.3, cutoff=1500)
    return place([(0.0, clunk), (0.05, 0.5 * sad)])


@sfx
def merge():
    t = times(0.7)
    f = freq_line(280, 1200, 0.7) * (1.0 + 0.05 * np.sin(2 * np.pi * 9 * t))
    swirl = osc("sine", f, 0.7) * np.sin(np.pi * t / 0.7) ** 1.5 * (0.7 + 0.3 * np.sin(2 * np.pi * 14 * t))
    sparkle = place([(0.35 + i * 0.05, 0.3 * tone(f2, 0.2, "sine", 0.002, 0.06, 0.05)) for i, f2 in enumerate([1568, 2093, 2637, 3136])])
    return reverb(place([(0.0, swirl), (0.0, sparkle)]), 0.9, 0.25)


@sfx
def talent():
    x = tone(1046, 0.5, "sine", 0.002, 0.25, 0.1) + 0.4 * tone(1568, 0.4, "sine", 0.002, 0.18, 0.1) + 0.2 * tone(2093, 0.3, "tri", 0.002, 0.1, 0.1)
    return reverb(x, 0.9, 0.25)


@sfx
def keystone():
    notes = [523, 659, 784, 1046, 1318]
    chord = place([(i * 0.045, 0.5 * bell(f, 1.3, 0.6, 0.6)) for i, f in enumerate(notes)])
    boom = thud(90, 40, 0.6, 0.4, 600)
    return reverb(place([(0.0, boom), (0.0, chord)]), 1.6, 0.35)


@sfx
def build():
    knock = lambda p: 0.8 * noise_burst(0.06, 700 * p, 2600 * p, 0.018) + thud(420 * p, 210 * p, 0.07, 0.0)
    return place([(0.0, knock(1.0)), (0.17, knock(1.05)), (0.34, 1.1 * knock(0.95))])


@sfx
def recruit():
    drum = lambda: thud(120, 70, 0.22, 0.4, 900)
    horn = tone(midi(67), 0.3, "saw", 0.04, None, 0.1, vib=0.004, cutoff=1400)
    return place([(0.0, drum()), (0.14, drum()), (0.28, 0.4 * horn)])


@sfx
def claim():
    coins = place([(0.0, coin(1.0)), (0.07, 0.8 * coin(1.12))])
    chime = place([(0.14, 0.5 * tone(1318, 0.35, "sine", 0.002, 0.15, 0.1)), (0.24, 0.5 * tone(1760, 0.4, "sine", 0.002, 0.2, 0.1))])
    return reverb(place([(0.0, coins), (0.0, chime)]), 0.7, 0.2)


@sfx
def donate():
    return place([(0.0, coin(0.95)), (0.07, 0.8 * coin(1.05)), (0.16, thud(200, 90, 0.12, 0.5, 900))])


@sfx
def error():
    buzz = lambda: tone(196, 0.08, "square", 0.002, None, 0.015, duty=0.4, cutoff=1400)
    return place([(0.0, buzz()), (0.12, buzz())])


@sfx
def prestige():
    rise_t = 1.3
    t = times(rise_t)
    rise = whoosh(rise_t, 200, 3000, 1.2, 0.95) * 0.8 + 0.3 * osc("sine", freq_line(150, 1200, rise_t), rise_t) * (t / rise_t) ** 2
    chord_notes = [midi(m) for m in (48, 55, 60, 64, 67, 72, 76)]
    pad = sum(tone(f * (1 + d), 2.4, "saw", 0.02, 1.0, 0.4, cutoff=2200) for f in chord_notes for d in (-0.003, 0.003)) / 10
    sparkle = place([(0.1 + i * 0.07, 0.25 * bell(midi(m), 0.8, 0.35, 0.5)) for i, m in enumerate((84, 88, 91, 96, 100))])
    boom = thud(80, 30, 0.9, 0.6, 500)
    return reverb(place([(0.0, rise), (rise_t, pad), (rise_t, sparkle), (rise_t, boom)]), 2.2, 0.35)


# Бой

@sfx
def attack_warrior():
    return whoosh(0.18, 3200, 600, 2.5, 0.25) + 0.15 * tone(freq_line(300, 150, 0.1), 0.1, "sine", 0.01, 0.04, 0.02)


@sfx
def attack_mage():
    t = times(0.2)
    bolt = osc("sine", freq_line(480, 1100, 0.2), 0.2) * env(0.2, 0.005, 0.07, 0.03) * (0.75 + 0.25 * np.sin(2 * np.pi * 40 * t))
    return bolt + 0.3 * tone(freq_line(960, 2200, 0.12), 0.12, "square", 0.002, 0.04, 0.02, duty=0.125, cutoff=5000) + 0.2 * noise_burst(0.15, lo=4000, decay=0.05)


@sfx
def attack_archer():
    string = pluck_ks(196, 0.25, 0.992) * env(0.25, 0.001, 0.08, 0.03)
    return lp(string, 3500) + 0.35 * whoosh(0.18, 4200, 1500, 2.0, 0.2)


@sfx
def hit():
    return thud(150, 55, 0.12, 0.6, 1800)


@sfx
def hit_2():
    return thud(175, 62, 0.11, 0.7, 2200)


@sfx
def hit_3():
    return thud(135, 50, 0.13, 0.55, 1500)


@sfx
def hit_crit():
    crack = noise_burst(0.05, lo=2500, decay=0.012)
    ring = 0.25 * bell(1760, 0.25, 0.12)
    zap = 0.4 * tone(freq_line(900, 420, 0.07), 0.07, "square", 0.001, 0.03, 0.01, duty=0.3, cutoff=4000)
    return 1.2 * thud(190, 50, 0.18, 0.8, 2500) + crack + ring + zap


@sfx
def hero_hurt():
    grunt = tone(freq_line(330, 170, 0.14), 0.14, "square", 0.002, 0.06, 0.02, duty=0.3, cutoff=1800)
    return grunt + 0.5 * noise_burst(0.1, hi=1200, decay=0.04)


@sfx
def monster_die():
    t = times(0.35)
    poof = svf(osc("noise", 0, 0.35), freq_line(3000, 250, 0.35), 0.8, "lp") * np.exp(-t / 0.1)
    drop = tone(freq_line(420, 85, 0.28), 0.28, "sine", 0.002, 0.1, 0.03)
    return poof + 0.6 * drop


@sfx
def gold():
    return 0.8 * coin(1.0, 0.13)


@sfx
def loot():
    tick = noise_burst(0.02, lo=3000, decay=0.004)
    sparkle = place([(0.02, 0.5 * tone(2637, 0.15, "tri", 0.001, 0.05, 0.03)), (0.08, 0.4 * tone(3520, 0.18, "tri", 0.001, 0.06, 0.04))])
    return place([(0.0, tick), (0.0, sparkle)])


@sfx
def elite():
    stab = (tone(110, 0.6, "saw", 0.01, 0.25, 0.1) + tone(116.5, 0.6, "saw", 0.01, 0.25, 0.1)) * 0.5
    return lp(stab, 900) + 0.6 * tone(55, 0.6, "sine", 0.01, 0.3, 0.1)


@sfx
def boss_slam():
    boom = tone(freq_line(70, 28, 0.8), 0.8, "sine", 0.002, 0.28, 0.05)
    return boom + 0.7 * noise_burst(0.6, hi=500, decay=0.2) + 0.4 * noise_burst(0.04, lo=1500, decay=0.01)


@sfx
def boss_shield():
    t = times(0.7)
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * 12 * t)
    x = sum(osc("sine", freq_line(f, f * 1.3, 0.7), 0.7) for f in (600, 900, 1200)) / 3 * trem * env(0.7, 0.08, 0.3, 0.1)
    return reverb(x, 0.8, 0.3)


@sfx
def wave_clear():
    return place([(i * 0.09, tone(f, 0.25, "tri", 0.002, 0.12, 0.05)) for i, f in enumerate([784, 988, 1175])])


@sfx
def skill_fire():
    t = times(0.75)
    roar = svf(osc("noise", 0, 0.75), np.interp(t, [0, 0.2, 0.75], [700, 3200, 1200]), 1.2, "bp") * env(0.75, 0.08, 0.3, 0.1)
    crackle = np.zeros(len(t))
    for pos in rng.integers(0, len(t) - 200, 40):
        crackle[pos:pos + 120] += rng.uniform(0.3, 1.0) * np.exp(-np.arange(120) / 18.0) * rng.choice([-1, 1])
    rumble = 0.5 * tone(90, 0.75, "sine", 0.05, 0.3, 0.1)
    return roar + 0.4 * hp(crackle, 1500) + rumble


@sfx
def skill_frost():
    parts = [(i * 0.05, 0.35 * tone(f * rng.uniform(0.99, 1.01), 0.8 - i * 0.05, "sine", 0.002, 0.25, 0.05))
             for i, f in enumerate([2093, 2637, 3136, 3951, 2349])]
    shimmer = (0.3 * noise_burst(0.6, lo=5000, decay=0.2, attack=0.05),)
    return reverb(place(parts + [(0.0, shimmer[0])]), 1.0, 0.35)


@sfx
def skill_lightning():
    t = times(0.5)
    gate = (rng.random(len(t) // 400 + 1) > 0.45).repeat(400)[:len(t)]
    crack = hp(osc("noise", 0, 0.5), 1500) * gate * np.exp(-t / 0.25)
    f = 120 * (1 + 0.5 * rng.random(len(t) // 800 + 1)).repeat(800)[:len(t)]
    buzz = osc("saw", f, 0.5) * np.exp(-t / 0.2) * 0.5
    return crack + lp(buzz, 3000)


@sfx
def skill_arcane():
    t = times(0.75)
    base = osc("saw", freq_line(220, 440, 0.75), 0.75)
    phased = svf(base, 900 + 700 * np.sin(2 * np.pi * 3 * t), 3.0, "bp")
    top = 0.4 * osc("sine", freq_line(880, 1760, 0.75), 0.75)
    return reverb((phased + top) * env(0.75, 0.05, 0.35, 0.1), 1.0, 0.3)


@sfx
def skill_slash():
    ring = 0.2 * bell(1500, 0.3, 0.1)
    return place([(0.0, whoosh(0.2, 2200, 380, 2.0, 0.25)), (0.12, 1.1 * whoosh(0.22, 2600, 350, 2.0, 0.25)), (0.12, ring)])


@sfx
def skill_heavy():
    rumble = noise_burst(0.9, hi=300, decay=0.35, attack=0.01)
    return 1.2 * thud(110, 35, 0.5, 0.8, 900) + rumble


@sfx
def skill_shout():
    horn = tone(midi(50), 0.85, "saw", 0.08, None, 0.2, vib=0.006, vib_rate=5.5) + 0.7 * tone(midi(57), 0.85, "saw", 0.1, None, 0.2, vib=0.006, vib_rate=5.2)
    return reverb(lp(horn, 1400), 1.0, 0.25)


@sfx
def skill_arrows():
    parts = [(0.0, 0.5 * lp(pluck_ks(196, 0.2, 0.99), 3000))]
    for i in range(4):
        parts.append((0.03 + i * 0.07, whoosh(0.2, rng.uniform(3600, 4800), rng.uniform(1200, 1700), 2.0, 0.2)))
    return place(parts)


@sfx
def skill_poison():
    parts = [(0.0, 0.2 * noise_burst(0.6, lo=3000, decay=0.25, attack=0.05))]
    for i in range(9):
        f0 = rng.uniform(280, 650)
        parts.append((rng.uniform(0.0, 0.5), 0.5 * tone(freq_line(f0, f0 * 1.8, 0.07), 0.07, "sine", 0.004, 0.03, 0.01)))
    return place(parts)


@sfx
def skill_snare():
    whip = hp(osc("noise", 0, 0.06), 2000) * env(0.06, 0.001, 0.012, 0.01)
    creak = lp(tone(freq_line(95, 80, 0.3), 0.3, "saw", 0.02, 0.1, 0.05), 900)
    return place([(0.0, whoosh(0.1, 1000, 5000, 2.0, 0.7)), (0.08, whip), (0.1, 0.5 * creak)])


@sfx
def skill_buff():
    notes = [523, 659, 784, 1046, 1318]
    arp = place([(i * 0.05, 0.4 * (tone(f, 0.35, "sine", 0.002, 0.15, 0.05) + 0.5 * tone(f * 2, 0.2, "tri", 0.002, 0.06, 0.05))) for i, f in enumerate(notes)])
    return reverb(arp, 0.9, 0.3)


@sfx
def skill_shield():
    t = times(0.7)
    bubble = sum(osc("sine", freq_line(f, f * 1.12, 0.7), 0.7) for f in (400, 600, 800)) / 3
    hum = 0.5 * osc("sine", 110, 0.7)
    return reverb((bubble * (0.8 + 0.2 * np.sin(2 * np.pi * 8 * t)) + hum) * env(0.7, 0.05, 0.35, 0.1), 0.8, 0.3)


@sfx
def skill_drain():
    t = times(0.75)
    swell = bp(osc("noise", 0, 0.75), 400, 1300) * (t / 0.75) ** 2
    wobble = osc("sine", freq_line(320, 140, 0.75) * (1 + 0.04 * np.sin(2 * np.pi * 7 * t)), 0.75) * np.sin(np.pi * t / 0.75)
    return reverb(swell + 0.6 * wobble, 0.8, 0.25)


# Уведомления

@sfx
def level_up():
    notes = [72, 76, 79, 84]
    lead = place([(i * 0.09, tone(midi(m), 0.45 if i == 3 else 0.12, "square", 0.002, 0.3 if i == 3 else None, 0.04, duty=0.25, cutoff=6000)) for i, m in enumerate(notes)])
    low = place([(i * 0.09, 0.5 * tone(midi(m - 12), 0.45 if i == 3 else 0.12, "tri", 0.002, None, 0.04)) for i, m in enumerate(notes)])
    sparkle = place([(0.3 + i * 0.05, 0.2 * tone(midi(96 + s), 0.2, "sine", 0.002, 0.07, 0.05)) for i, s in enumerate((0, 4, 7, 12))])
    return reverb(place([(0.0, lead), (0.0, low), (0.0, sparkle)]), 1.0, 0.25)


@sfx
def loot_rare():
    return reverb(place([(0.0, 0.6 * bell(1318, 0.5, 0.3, 0.4)), (0.1, 0.6 * bell(1760, 0.6, 0.35, 0.4))]), 0.9, 0.3)


@sfx
def loot_epic():
    notes = [1046, 1318, 1568, 2093]
    return reverb(place([(i * 0.08, 0.5 * bell(f, 0.7, 0.35, 0.5)) for i, f in enumerate(notes)]), 1.1, 0.3)


@sfx
def loot_legendary():
    notes = [72, 76, 79, 84, 88]
    lead = place([(i * 0.08, tone(midi(m), 0.6 if i == 4 else 0.14, "square", 0.002, 0.35 if i == 4 else None, 0.04, duty=0.25, cutoff=5000)) for i, m in enumerate(notes)])
    bells = place([(0.35 + i * 0.06, 0.35 * bell(midi(m), 0.9, 0.4, 0.5)) for i, m in enumerate((91, 96, 100, 103))])
    pad = 0.25 * sum(tone(midi(m), 1.2, "saw", 0.05, 0.5, 0.2, cutoff=2500) for m in (60, 64, 67)) / 3
    return reverb(place([(0.0, lead), (0.0, bells), (0.3, pad)]), 1.5, 0.35)


@sfx
def treasure():
    scale = [0, 2, 4, 7, 9]
    notes = [72 + scale[i % 5] + 12 * (i // 5) for i in range(10)]
    harp = place([(i * 0.045, 0.4 * lp(pluck_ks(midi(m), 0.6, 0.996), 5000)) for i, m in enumerate(notes)])
    return reverb(place([(0.0, harp), (0.45, 0.4 * bell(midi(96), 0.9, 0.45, 0.6))]), 1.3, 0.35)


@sfx
def boss_appear():
    horn = (tone(midi(38), 1.3, "saw", 0.12, None, 0.3, vib=0.004) + tone(midi(45), 1.3, "saw", 0.14, None, 0.3, vib=0.004)) * 0.5
    drum = lambda: thud(65, 32, 0.6, 0.6, 400)
    return reverb(place([(0.0, drum()), (0.0, lp(horn, 900)), (0.55, drum()), (0.8, 0.8 * drum())]), 1.6, 0.3)


@sfx
def boss_defeated():
    notes = [(0.0, 67, 0.1), (0.12, 72, 0.1), (0.24, 76, 0.1), (0.36, 79, 0.25), (0.66, 76, 0.1), (0.78, 84, 0.7)]
    lead = place([(t0, tone(midi(m), d, "square", 0.002, None, 0.05, duty=0.25, cutoff=5000)) for t0, m, d in notes])
    low = place([(t0, 0.45 * tone(midi(m - 12), d, "tri", 0.002, None, 0.05)) for t0, m, d in notes])
    chord = 0.3 * sum(tone(midi(m), 0.9, "saw", 0.02, 0.45, 0.2, cutoff=2400) for m in (60, 64, 67, 72)) / 4
    return reverb(place([(0.0, lead), (0.0, low), (0.78, chord), (0.78, 0.4 * thud(80, 35, 0.4, 0.4, 500))]), 1.4, 0.3)


@sfx
def hero_died():
    notes = [67, 66, 65, 64]
    x = place([(i * 0.3, tone(midi(m), 0.6 if i == 3 else 0.32, "tri", 0.01, None, 0.08, vib=0.008 if i == 3 else 0.0, vib_rate=5)) for i, m in enumerate(notes)])
    bass = 0.5 * tone(midi(40), 1.5, "sine", 0.05, 0.6, 0.2)
    return reverb(place([(0.0, x), (0.0, bass)]), 1.2, 0.3)


@sfx
def construction_done():
    return reverb(place([(0.0, 0.6 * bell(midi(79), 0.8, 0.4, 0.5)), (0.18, 0.6 * bell(midi(84), 1.0, 0.5, 0.5))]), 1.0, 0.3)


@sfx
def units_ready():
    horn = place([(0.0, tone(midi(67), 0.22, "saw", 0.03, None, 0.05, vib=0.004)), (0.24, tone(midi(72), 0.45, "saw", 0.03, None, 0.12, vib=0.005))])
    return reverb(lp(horn, 1600), 0.8, 0.25)


@sfx
def attack_alarm():
    ding = lambda: 0.5 * bell(1200, 0.45, 0.2, 0.8) + 0.35 * bell(1272, 0.45, 0.2, 0.8)
    return reverb(place([(0.0, ding()), (0.22, ding()), (0.44, ding())]), 0.8, 0.2)


@sfx
def report():
    pop = tone(freq_line(880, 1320, 0.06), 0.1, "sine", 0.002, 0.04, 0.03)
    return place([(0.0, pop), (0.07, 0.5 * tone(1760, 0.2, "sine", 0.002, 0.07, 0.05))])


@sfx
def guild_invite():
    notes = [74, 79, 83]
    return reverb(place([(i * 0.1, 0.6 * tone(midi(m), 0.4, "tri", 0.003, 0.18, 0.08)) for i, m in enumerate(notes)]), 0.9, 0.25)


@sfx
def chat():
    return place([(0.0, tone(1200, 0.08, "sine", 0.002, 0.03, 0.02)), (0.07, 0.8 * tone(1600, 0.1, "sine", 0.002, 0.04, 0.03))])


@sfx
def quest_done():
    notes = [76, 79, 84]
    lead = place([(i * 0.08, tone(midi(m), 0.3 if i == 2 else 0.09, "square", 0.002, 0.15 if i == 2 else None, 0.03, duty=0.5, cutoff=3500)) for i, m in enumerate(notes)])
    return reverb(lead, 0.8, 0.2)


@sfx
def rest_start():
    x = place([(0.0, tone(660, 0.35, "sine", 0.06, None, 0.1)), (0.3, tone(440, 0.5, "sine", 0.08, None, 0.25))])
    return reverb(x, 1.0, 0.3)


@sfx
def rest_end():
    x = place([(0.0, tone(440, 0.25, "sine", 0.03, None, 0.08)), (0.2, tone(660, 0.45, "sine", 0.04, None, 0.2))])
    return reverb(x, 0.9, 0.25)


# --- Музыка -----------------------------------------------------------------------------

SCALES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
}


def instrument(name, freq, dur, vel=1.0):
    """Нота инструмента (с хвостом затухания, поэтому длиннее dur)."""
    tail = {"pad": 0.6, "organ": 0.12, "musicbox": 0.8, "pluck": 0.4, "harp": 0.8, "bell": 1.0}.get(name, 0.08)
    total = dur + tail
    if name == "flute":
        t = times(total)
        vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.15) / 0.2, 0.0, 1.0)
        x = osc("sine", freq * vib, total) + 0.18 * osc("sine", 2 * freq * vib, total) + 0.05 * osc("sine", 3 * freq * vib, total)
        x += 0.04 * bp(osc("noise", 0, total), freq, min(freq * 3, 9000))
        x *= env(total, 0.04, None, tail + 0.02)
    elif name == "pluck":
        x = osc("tri", freq, total) * env(total, 0.002, 0.22, 0.05) + 0.25 * osc("square", freq, total, 0.25) * env(total, 0.002, 0.06, 0.05)
        x = lp(x, 3000)
    elif name == "harp":
        x = lp(pluck_ks(freq, total, 0.997), 4500) * env(total, 0.001, 0.5, 0.1)
    elif name == "musicbox":
        x = (osc("sine", freq, total) + 0.25 * osc("sine", 2 * freq, total) * env(total, 0.001, 0.15, 0.1) + 0.12 * osc("sine", 5.04 * freq, total) * env(total, 0.001, 0.05, 0.1)) * env(total, 0.001, 0.45, 0.1)
    elif name == "bell":
        x = bell(freq, total, 0.7, 0.4)
    elif name == "organ":
        x = sum(w * osc("sine", freq * h, total) for h, w in ((1, 1.0), (2, 0.5), (3, 0.28), (4, 0.14)))
        x = lp(x * env(total, 0.05, None, tail + 0.02), 2500)
    elif name == "horn":
        t = times(total)
        vib = 1.0 + 0.005 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.2) / 0.2, 0.0, 1.0)
        x = osc("saw", freq * vib, total) * env(total, 0.06, None, tail + 0.03)
        x = lp(x, min(freq * 5, 3500))
    elif name == "pad":
        x = sum(osc("saw", freq * (1 + d), total) for d in (-0.004, 0.0, 0.004)) / 3
        x = lp(x * env(total, 0.35, None, tail + 0.05), 1300)
    elif name == "strings":
        x = sum(osc("saw", freq * (1 + d), total) for d in (-0.003, 0.003)) / 2
        x = lp(x * env(total, 0.12, None, tail + 0.05), 2200)
    elif name == "square_lead":
        t = times(total)
        vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.15, 0.0, 1.0)
        x = (osc("square", freq * vib, total, 0.25) + 0.5 * osc("square", freq * 1.004 * vib, total, 0.5)) / 1.5
        x = lp(x * env(total, 0.008, None, tail + 0.02), 4200)
    elif name == "bass_tri":
        x = osc("tri", freq, total) * env(total, 0.004, None, tail + 0.02)
    elif name == "bass_saw":
        x = lp(osc("saw", freq, total) * env(total, 0.004, 0.25, 0.04, 0.5), 700)
    elif name == "bass_sine":
        x = osc("sine", freq, total) * env(total, 0.01, None, tail + 0.03) + 0.2 * osc("tri", freq * 2, total) * env(total, 0.01, 0.1, 0.03)
    elif name == "power":
        x = sum(osc("saw", freq * r * (1 + d), total) for r in (1.0, 1.5, 2.0) for d in (-0.003, 0.003)) / 6
        x = lp(x * env(total, 0.005, 0.4, 0.05, 0.6), 1800)
    else:
        raise ValueError(name)
    return x * vel


def drum(name):
    if name == "kick":
        return tone(freq_line(150, 45, 0.18), 0.18, "sine", 0.001, 0.08, 0.02) + 0.2 * noise_burst(0.01, lo=2000, decay=0.003)
    if name == "snare":
        return 0.7 * noise_burst(0.16, 1000, 6000, 0.05) + 0.5 * tone(190, 0.08, "tri", 0.001, 0.03, 0.02)
    if name == "hat":
        return noise_burst(0.05, lo=7000, decay=0.012)
    if name == "shaker":
        return noise_burst(0.07, lo=5000, decay=0.03, attack=0.015)
    if name == "tom":
        return tone(freq_line(130, 80, 0.3), 0.3, "sine", 0.001, 0.12, 0.03)
    if name == "clock":
        return 0.6 * tone(2400, 0.03, "sine", 0.0005, 0.006, 0.01) + noise_burst(0.02, 2000, 5000, 0.004)
    raise ValueError(name)


TRACKS = {
    # Лес: светлый мажор, флейта, щипки, лёгкий шейкер.
    "forest": dict(bpm=92, root=62, scale="major", prog=[0, 4, 5, 3], lead="flute", lead_vol=0.5,
                   arp="pluck", arp_vol=0.28, arp_rate=2, pad="pad", pad_vol=0.18, bass="bass_tri", bass_vol=0.4,
                   bass_style="root_fifth", drums={"kick": "x.......x.......", "shaker": "..x...x...x...x.", "hat": "....x.......x..."},
                   drum_vol={"kick": 0.35, "shaker": 0.12, "hat": 0.08}, seed=11, reverb=0.3),
    # Кладбище: минор, музыкальная шкатулка, орган, тиканье часов.
    "graveyard": dict(bpm=74, root=57, scale="minor", prog=[0, 5, 3, 4], lead="musicbox", lead_vol=0.45,
                      arp="organ", arp_vol=0.0, arp_rate=0, pad="organ", pad_vol=0.16, bass="bass_sine", bass_vol=0.45,
                      bass_style="half", drums={"clock": "x...x...x...x...", "tom": "x.............x."},
                      drum_vol={"clock": 0.08, "tom": 0.25}, seed=23, reverb=0.45),
    # Горы: дорийский лад, валторна, струнные, марш.
    "mountains": dict(bpm=100, root=52, scale="dorian", prog=[0, 3, 6, 4], lead="horn", lead_vol=0.5,
                      arp="harp", arp_vol=0.22, arp_rate=2, pad="strings", pad_vol=0.16, bass="bass_saw", bass_vol=0.4,
                      bass_style="walk", drums={"kick": "x.......x.......", "snare": "....x.......x.x.", "hat": "x.x.x.x.x.x.x.x.", "tom": "..............x."},
                      drum_vol={"kick": 0.35, "snare": 0.18, "hat": 0.05, "tom": 0.2}, seed=37, reverb=0.35, lead_octave=0),
    # Проклятые земли: фригийский лад, тревожный квадратный лид, пульс «сердцебиения».
    "cursed": dict(bpm=84, root=49, scale="phrygian", prog=[0, 1, 0, 6], lead="square_lead", lead_vol=0.32,
                   arp="bell", arp_vol=0.12, arp_rate=1, pad="pad", pad_vol=0.2, bass="bass_saw", bass_vol=0.42,
                   bass_style="pulse", drums={"kick": "x..x............", "hat": "........x......."},
                   drum_vol={"kick": 0.45, "hat": 0.06}, seed=41, reverb=0.4),
    # Босс: гармонический минор, быстрый бас восьмыми, квинты, полный бит.
    "boss": dict(bpm=140, root=50, scale="harmonic", prog=[0, 5, 3, 4], lead="square_lead", lead_vol=0.38,
                 arp="power", arp_vol=0.22, arp_rate=0, pad="power", pad_vol=0.2, bass="bass_saw", bass_vol=0.45,
                 bass_style="eighths", drums={"kick": "x...x...x...x.x.", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."},
                 drum_vol={"kick": 0.5, "snare": 0.3, "hat": 0.08}, seed=53, reverb=0.25, bars=24),
    # Создание героя: спокойный мажор, шкатулка и пэд, без ударных.
    "menu": dict(bpm=70, root=60, scale="major", prog=[0, 5, 3, 4], lead="musicbox", lead_vol=0.4,
                 arp="harp", arp_vol=0.2, arp_rate=1, pad="pad", pad_vol=0.2, bass="bass_sine", bass_vol=0.35,
                 bass_style="half", drums={}, drum_vol={}, seed=67, reverb=0.45, bars=16),
}

RHYTHMS = [
    [1, 1, 1, 1], [1.5, 0.5, 1, 1], [0.5, 0.5, 1, 2], [2, 1, 1], [1, 0.5, 0.5, 2], [3, 1], [1, 1, 2],
    [0.5, 0.5, 0.5, 0.5, 2], [1, 1, 1.5, 0.5],
]


class Composer:
    def __init__(self, cfg):
        self.cfg = cfg
        self.rand = np.random.default_rng(cfg["seed"])
        self.scale = SCALES[cfg["scale"]]
        self.beat = 60.0 / cfg["bpm"]
        self.bar = 4 * self.beat

    def pitch(self, degree, octave_shift=0):
        """Ступень лада (может быть отрицательной/больше 7) → MIDI-нота относительно тоники."""
        octave, step = divmod(degree, 7)
        return self.cfg["root"] + 12 * (octave + octave_shift) + self.scale[step]

    def chord_degrees(self, chord):
        return [chord, chord + 2, chord + 4]

    def motif(self):
        """Мотив на 2 такта: ритм + шаги мелодии (контур), без привязки к аккорду."""
        rhythm = list(self.rand.choice(len(RHYTHMS), 2))
        steps = []
        for bar_index in rhythm:
            for i, _ in enumerate(RHYTHMS[bar_index]):
                steps.append(int(self.rand.choice([-2, -1, -1, 0, 1, 1, 2, 3, -3])) if steps or i else 0)
        return rhythm, steps

    def realize(self, motif, chords, start, register):
        """Мотив на конкретных аккордах: сильные доли — к ближайшему звуку аккорда."""
        rhythm, steps = motif
        notes = []
        degree = start
        k = 0
        for bar, bar_index in enumerate(rhythm):
            beat = 0.0
            chord_tones = self.chord_degrees(chords[bar])
            for length in RHYTHMS[bar_index]:
                degree += steps[k]
                k += 1
                degree = int(np.clip(degree, register - 4, register + 6))
                if beat in (0.0, 2.0):
                    candidates = [c + 7 * o for c in chord_tones for o in range(-2, 3)]
                    degree = min(candidates, key=lambda c: (abs(c - degree), c))
                rest = self.rand.random() < 0.08 and beat > 0
                notes.append((bar, beat, length, None if rest else degree))
                beat += length
        return notes, degree

    def melody(self, chords, register):
        """8 тактов: мотив A, его повтор на других аккордах, мотив B, каденция на тонике."""
        a = self.motif()
        b = self.motif()
        out = []
        degree = register
        for block, motif in enumerate([a, a, b, None]):
            bar0 = block * 2
            if motif is None:
                n1, degree = self.realize(self.motif(), chords[bar0:bar0 + 2], degree, register)
                n1 = [n for n in n1 if n[0] == 0]
                tonic = min((7 * o for o in range(-1, 3)), key=lambda c: abs(c - degree))
                n1.append((1, 0.0, 3.0, tonic))
                out += [(bar0 + bar, beat, length, d) for bar, beat, length, d in n1]
                continue
            notes, degree = self.realize(motif, chords[bar0:bar0 + 2], degree, register)
            out += [(bar0 + bar, beat, length, d) for bar, beat, length, d in notes]
        return out

    def render(self):
        cfg = self.cfg
        bars = cfg.get("bars", 32)
        loop_len = n_of(bars * self.bar)
        buf = {k: np.zeros(loop_len + n_of(3.0)) for k in ("lead", "arp", "pad", "bass", "drums")}

        def put(track, start_sec, x):
            s = n_of(start_sec)
            if s < len(buf[track]):
                end = min(len(buf[track]), s + len(x))
                buf[track][s:end] += x[:end - s]

        prog = cfg["prog"]
        chords = [prog[i % len(prog)] for i in range(bars)]
        sections = bars // 8
        # Мелодии секций: A, A (вариант), B (выше), A. Первая секция — вступление без мелодии (если секций ≥ 4).
        melody_a = self.melody(chords[:8], 7 + cfg.get("lead_octave", 0) * 7)
        melody_b = self.melody(chords[:8], 9 + cfg.get("lead_octave", 0) * 7)
        plan = ["intro", "A", "B", "A"] if sections >= 4 else (["A", "B", "A"] if sections == 3 else ["A", "B"])
        for s, kind in enumerate(plan):
            base_bar = s * 8
            if kind == "intro":
                continue
            melody = melody_a if kind == "A" else melody_b
            for bar, beat, length, degree in melody:
                if degree is None:
                    continue
                when = (base_bar + bar) * self.bar + beat * self.beat
                vel = 1.0 if beat in (0.0, 2.0) else 0.85
                put("lead", when, instrument(cfg["lead"], midi(self.pitch(degree)), length * self.beat * 0.95, vel))

        for bar in range(bars):
            t0 = bar * self.bar
            chord = chords[bar]
            tones = [self.pitch(d) for d in self.chord_degrees(chord)]
            if cfg["pad_vol"] > 0:
                for m in tones:
                    put("pad", t0, instrument(cfg["pad"], midi(m), self.bar * 0.98, 1.0) / 3)
            rate = cfg["arp_rate"]
            if rate and cfg["arp_vol"] > 0:
                pattern = [0, 1, 2, 1, 0, 2, 1, 2] if rate >= 2 else [0, 1, 2, 1]
                step = self.beat / rate
                for i in range(int(4 * rate)):
                    idx = pattern[i % len(pattern)]
                    m = self.pitch(self.chord_degrees(chord)[idx], 1)
                    put("arp", t0 + i * step, instrument(cfg["arp"], midi(m), step * 0.9, 0.9 if i % 2 else 1.0))
            root = self.pitch(chord, -1)
            fifth = self.pitch(chord + 4, -1)
            style = cfg["bass_style"]
            b = cfg["bass"]
            if style == "root_fifth":
                seq = [(0, root, 2), (2, fifth, 1.5), (3.5, root, 0.5)]
            elif style == "half":
                seq = [(0, root, 2), (2, root if bar % 2 else fifth, 2)]
            elif style == "walk":
                seq = [(0, root, 1), (1, fifth, 1), (2, root + 12, 1), (3, fifth, 1)]
            elif style == "pulse":
                seq = [(0, root, 0.4), (0.75, root, 0.4), (2, root, 0.4), (2.75, root, 0.4)]
            else:  # eighths
                seq = [(i * 0.5, root if i != 6 else fifth, 0.45) for i in range(8)]
            for beat, m, length in seq:
                put("bass", t0 + beat * self.beat, instrument(b, midi(m), length * self.beat))

            intro = plan[bar // 8] == "intro" if bar // 8 < len(plan) else False
            for name, pattern in cfg["drums"].items():
                vol = cfg["drum_vol"][name] * (0.5 if intro else 1.0)
                if intro and name in ("snare",):
                    continue
                for i, c in enumerate(pattern):
                    if c == "x":
                        put("drums", t0 + i * self.beat / 4, drum(name) * vol * self.rand.uniform(0.85, 1.0))

        mix = (cfg["lead_vol"] * buf["lead"] + cfg["arp_vol"] * buf["arp"] + cfg["pad_vol"] * buf["pad"]
               + cfg["bass_vol"] * buf["bass"] + buf["drums"])
        # Хвост после конца петли переносится в её начало — петля без щелчка и без обрыва реверберации.
        looped = mix[:loop_len].copy()
        tail = mix[loop_len:]
        looped[:len(tail)] += tail[:loop_len]
        wet = reverb(looped, 2.0, cfg["reverb"], 4500, seed=cfg["seed"], wrap=loop_len)
        wet = np.tanh(wet / (np.max(np.abs(wet)) + 1e-9) * 1.3) / np.tanh(1.3)
        return wet * 0.8


# --- Запуск -----------------------------------------------------------------------------

def write(path, x):
    """OGG Vorbis. Пишем кусками: libsndfile под Windows падает (переполнение стека) на больших блоках."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.asarray(x, np.float32)
    with sf.SoundFile(path, "w", SR, 1, format="OGG", subtype="VORBIS") as out:
        try:
            out.compression_level = 0.55
        except (AttributeError, RuntimeError):
            pass
        for start in range(0, len(data), 4096):
            out.write(data[start:start + 4096])


def main(args):
    keep = "--keep" in args
    names = [a for a in args if not a.startswith("--")]
    want_sfx = not names or "sfx" in names
    want_music = not names or "music" in names
    chosen = set(names) - {"sfx", "music"}
    global rng
    for name, fn in SFX.items():
        if not (want_sfx or name in chosen):
            continue
        path = os.path.join(SFX_DIR, name + ".ogg")
        if keep and os.path.exists(path):
            continue
        rng = np.random.default_rng(sum(map(ord, name)))
        write(path, finish(fn()))
        print("sfx  ", name)
    for name, cfg in TRACKS.items():
        if not (want_music or name in chosen):
            continue
        path = os.path.join(MUSIC_DIR, name + ".ogg")
        if keep and os.path.exists(path):
            continue
        rng = np.random.default_rng(cfg["seed"])
        x = Composer(cfg).render()
        write(path, x)
        print("music", name, "%.1f s" % (len(x) / SR))


if __name__ == "__main__":
    main(sys.argv[1:])

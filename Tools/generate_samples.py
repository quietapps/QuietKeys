#!/usr/bin/env python3
"""Procedural mechanical-keyboard sample synthesizer for Quiet Keys.

Generates every switch profile as a folder of WAV files plus a manifest.json.
All samples are original, synthesized from parametric physical models — no
recordings from other apps are used.

Usage:  python3 Tools/generate_samples.py [output_dir]
Default output: QuietKeys/Resources/Profiles
"""

import json
import os
import sys
import wave

import numpy as np

SR = 48_000


# ─── DSP primitives ────────────────────────────────────────────────────────

def env_exp(n, decay):
    """Exponential decay envelope, `decay` in seconds to -60 dB."""
    t = np.arange(n) / SR
    return np.exp(-6.907 * t / decay)


def noise(n, rng):
    return rng.standard_normal(n)


def bandpass(x, freq, q):
    """Simple biquad bandpass (constant skirt gain)."""
    w0 = 2 * np.pi * freq / SR
    alpha = np.sin(w0) / (2 * q)
    b = np.array([q * alpha, 0.0, -q * alpha])
    a = np.array([1 + alpha, -2 * np.cos(w0), 1 - alpha])
    b /= a[0]
    a /= a[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        y[i] = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, y[i]
    return y


def lowpass(x, freq):
    """One-pole lowpass."""
    k = 1.0 - np.exp(-2 * np.pi * freq / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += k * (x[i] - acc)
        y[i] = acc
    return y


def ping(n, freq, decay, phase=0.0):
    """Damped sinusoid — metallic/resonant partial."""
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t + phase) * env_exp(n, decay)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def write_wav(path, x):
    x16 = np.clip(x, -1, 1)
    x16 = (x16 * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(x16.tobytes())


# ─── Switch physical model ─────────────────────────────────────────────────
#
# Every keypress sound is layered from:
#   1. contact  — very short broadband transient (slider hitting housing)
#   2. body     — bandpassed noise burst, the "clack"/"thock" color
#   3. bottom   — low sine thump (bottom-out into the plate/case)
#   4. click    — optional metallic ring (click jacket / spring ping)

def synth_press(p, rng):
    dur = p.get("dur", 0.16)
    n = int(SR * dur)
    jitter = lambda v, pct: v * (1 + rng.uniform(-pct, pct))

    out = np.zeros(n)

    # 1. contact transient
    cn = int(SR * 0.004)
    contact = noise(cn, rng) * env_exp(cn, 0.0025) * p.get("contact", 0.7)
    out[:cn] += contact

    # 2. body noise
    body_f = jitter(p["body_freq"], 0.06)
    body = bandpass(noise(n, rng), body_f, p.get("body_q", 1.2))
    body *= env_exp(n, jitter(p.get("body_decay", 0.035), 0.1))
    out += body * p.get("body", 1.0)

    # 3. bottom-out thump
    thump_f = jitter(p.get("thump_freq", 110), 0.05)
    thump = ping(n, thump_f, p.get("thump_decay", 0.05))
    # slightly delayed — bottom-out follows first contact
    d = int(SR * 0.002)
    out[d:] += thump[:-d] * p.get("thump", 0.5)

    # 4. click ring (clicky / buckling spring)
    for freq, amp, dec in p.get("rings", []):
        out += ping(n, jitter(freq, 0.03), dec, rng.uniform(0, np.pi)) * amp

    if p.get("lp"):
        out = lowpass(out, p["lp"])
    return normalize(out, p.get("peak", 0.85))


def synth_release(p, rng):
    """Release = softer, brighter, shorter version of the press."""
    q = dict(p)
    q["dur"] = min(0.09, p.get("dur", 0.16) * 0.6)
    q["body_freq"] = p["body_freq"] * 1.25
    q["body_decay"] = p.get("body_decay", 0.035) * 0.55
    q["thump"] = p.get("thump", 0.5) * 0.25
    q["contact"] = p.get("contact", 0.7) * 0.8
    q["rings"] = [(f * 1.1, a * 0.25, d * 0.5) for f, a, d in p.get("rings", [])]
    q["peak"] = p.get("peak", 0.85) * 0.45
    return synth_press(q, rng)


def synth_lizard(rng, up=False):
    """Novelty 'Lizard' — a tiny gecko chirp per keystroke."""
    dur = 0.09 if not up else 0.05
    n = int(SR * dur)
    t = np.arange(n) / SR
    f0 = rng.uniform(1150, 1450) * (1.35 if up else 1.0)
    sweep = f0 * (1 + 1.8 * t / dur)          # rising chirp
    phase = 2 * np.pi * np.cumsum(sweep) / SR
    x = np.sin(phase) * env_exp(n, dur * 0.5)
    x += 0.25 * np.sin(2 * phase) * env_exp(n, dur * 0.3)   # raspy 2nd harmonic
    cn = int(SR * 0.003)
    x[:cn] += noise(cn, rng) * env_exp(cn, 0.002) * 0.3     # tongue click
    return normalize(x, 0.5 if up else 0.75)


# ─── Profile definitions ───────────────────────────────────────────────────
#
# body_freq — center of the noise "clack" (higher = clackier, lower = thockier)
# rings     — [(freq, amp, decay)] metallic partials for clicky switches

LINEAR = dict(body=1.0, contact=0.6)
TACTILE = dict(body=1.1, contact=0.9)

PROFILES = [
    # brand, name, params, type
    ("IQUNIX", "MQ80", "tactile", dict(TACTILE, body_freq=950, body_q=1.0,
        thump_freq=95, thump=0.85, thump_decay=0.07, body_decay=0.045, lp=6500)),
    ("Lofree", "Flow 2 Surfer", "linear", dict(LINEAR, body_freq=1500, body_q=1.4,
        thump_freq=130, thump=0.4, body_decay=0.028, lp=9000)),
    ("Lofree", "Flow 2 Void", "linear", dict(LINEAR, body_freq=800, body_q=1.1,
        thump_freq=88, thump=0.9, thump_decay=0.08, body_decay=0.05, lp=5200)),
    ("Lofree", "Flow 2 Pulse", "tactile", dict(TACTILE, body_freq=1250, body_q=1.3,
        thump_freq=115, thump=0.6, body_decay=0.033, lp=7500)),
    ("Akko", "Piano Pro", "linear", dict(LINEAR, body_freq=1050, body_q=0.9,
        thump_freq=105, thump=0.8, thump_decay=0.09, body_decay=0.055, lp=6000,
        rings=[(2100, 0.06, 0.09)])),
    ("Akko", "CS Jelly Black", "linear", dict(LINEAR, body_freq=900, body_q=1.2,
        thump_freq=100, thump=0.7, body_decay=0.04, lp=6800)),
    ("Akko", "V3 Cream Yellow Pro", "linear", dict(LINEAR, body_freq=1100, body_q=1.0,
        thump_freq=112, thump=0.65, body_decay=0.042, lp=7200)),
    ("Akko", "Clicky Pink", "clicky", dict(body=0.8, contact=0.9, body_freq=1900,
        body_q=1.6, thump_freq=140, thump=0.3, body_decay=0.025,
        rings=[(3400, 0.5, 0.05), (5200, 0.3, 0.03)])),
    ("Keychron", "K2 Max · K Pro Red", "linear", dict(LINEAR, body_freq=1350, body_q=1.3,
        thump_freq=120, thump=0.5, body_decay=0.03, lp=8200)),
    ("Keychron", "K2 Max · K Pro Brown", "tactile", dict(TACTILE, body_freq=1150, body_q=1.1,
        thump_freq=108, thump=0.65, body_decay=0.038, lp=7000)),
    ("Aflion", "Carrot Orange", "tactile", dict(TACTILE, body_freq=1300, body_q=1.2,
        thump_freq=118, thump=0.55, body_decay=0.034, lp=7800)),
    ("Durock", "Alpaca", "linear", dict(LINEAR, body_freq=1200, body_q=1.5,
        thump_freq=110, thump=0.6, body_decay=0.032, lp=7600)),
    ("Gateron", "Ink Black", "linear", dict(LINEAR, body_freq=850, body_q=1.2,
        thump_freq=92, thump=0.9, thump_decay=0.085, body_decay=0.05, lp=5600)),
    ("Gateron", "Ink Red", "linear", dict(LINEAR, body_freq=1400, body_q=1.4,
        thump_freq=125, thump=0.45, body_decay=0.029, lp=8600)),
    ("Gateron", "Turquoise Tealios", "linear", dict(LINEAR, body_freq=1600, body_q=1.6,
        thump_freq=132, thump=0.4, body_decay=0.027, lp=9400)),
    ("NovelKeys", "Cream", "linear", dict(LINEAR, body_freq=1750, body_q=1.1,
        thump_freq=128, thump=0.5, body_decay=0.03, lp=10_000,
        rings=[(2600, 0.08, 0.06)])),
    ("Drop", "Holy Panda", "tactile", dict(body=1.25, contact=1.0, body_freq=1000,
        body_q=0.95, thump_freq=98, thump=0.95, thump_decay=0.075,
        body_decay=0.048, lp=6200)),
    ("Kailh", "Box Navy", "clicky", dict(body=0.9, contact=1.0, body_freq=2100,
        body_q=1.5, thump_freq=150, thump=0.35, body_decay=0.024,
        rings=[(3000, 0.65, 0.06), (4700, 0.4, 0.04), (6100, 0.2, 0.025)])),
    ("IBM", "Buckling Spring", "clicky", dict(body=0.85, contact=1.1, body_freq=1700,
        body_q=1.3, thump_freq=135, thump=0.5, thump_decay=0.06, body_decay=0.03,
        rings=[(2400, 0.55, 0.11), (3800, 0.45, 0.08), (5600, 0.25, 0.05)],
        dur=0.2)),
    ("Topre", "Classic", "tactile", dict(body=1.0, contact=0.5, body_freq=700,
        body_q=0.8, thump_freq=82, thump=1.0, thump_decay=0.1,
        body_decay=0.06, lp=4200, dur=0.18)),
    ("Alps", "SKCM Blue", "clicky", dict(body=0.9, contact=1.0, body_freq=1850,
        body_q=1.4, thump_freq=138, thump=0.4, body_decay=0.028,
        rings=[(2900, 0.5, 0.07), (4400, 0.3, 0.045)])),
    ("Quirky", "Lizard", "novelty", None),  # special-cased
]

MOUSE = {
    "mouse_left": dict(body=0.9, contact=1.0, body_freq=2400, body_q=1.8,
        thump_freq=180, thump=0.3, body_decay=0.018, dur=0.07,
        rings=[(4200, 0.3, 0.02)]),
    "mouse_right": dict(body=0.9, contact=1.0, body_freq=2100, body_q=1.8,
        thump_freq=165, thump=0.3, body_decay=0.02, dur=0.07,
        rings=[(3700, 0.3, 0.022)]),
    "mouse_middle": dict(body=0.85, contact=0.9, body_freq=1800, body_q=1.6,
        thump_freq=150, thump=0.35, body_decay=0.022, dur=0.08,
        rings=[(3200, 0.25, 0.025)]),
}

N_DOWN = 4   # round-robin variants per key class
N_UP = 3


def slug(brand, name):
    s = f"{brand}-{name}".lower()
    for ch in " ·/":
        s = s.replace(ch, "-")
    while "--" in s:
        s = s.replace("--", "-")
    return s.strip("-").replace("'", "")


def key_variant(base, kind):
    """Parameter tweaks for special keys — bigger keys sound deeper/looser."""
    p = dict(base)
    if kind == "space":
        p["body_freq"] = base["body_freq"] * 0.72
        p["thump"] = base.get("thump", 0.5) * 1.4
        p["thump_freq"] = base.get("thump_freq", 110) * 0.85
        p["dur"] = base.get("dur", 0.16) * 1.25
        p["rings"] = base.get("rings", []) + [(base["body_freq"] * 1.9, 0.05, 0.05)]
    elif kind == "return":
        p["body_freq"] = base["body_freq"] * 0.85
        p["thump"] = base.get("thump", 0.5) * 1.2
        p["dur"] = base.get("dur", 0.16) * 1.1
    elif kind == "delete":
        p["body_freq"] = base["body_freq"] * 0.92
        p["thump"] = base.get("thump", 0.5) * 1.1
    return p


def main():
    out_root = sys.argv[1] if len(sys.argv) > 1 else "QuietKeys/Resources/Profiles"
    os.makedirs(out_root, exist_ok=True)

    for brand, name, sw_type, params in PROFILES:
        pid = slug(brand, name)
        pdir = os.path.join(out_root, pid)
        os.makedirs(pdir, exist_ok=True)
        rng = np.random.default_rng(abs(hash(pid)) % (2**32))

        keys = {}
        for kind in ("default", "space", "return", "delete"):
            downs, ups = [], []
            for i in range(N_DOWN):
                fn = f"{kind}_down_{i + 1}.wav"
                if params is None:  # Lizard
                    x = synth_lizard(rng)
                else:
                    x = synth_press(key_variant(params, kind), rng)
                write_wav(os.path.join(pdir, fn), x)
                downs.append(fn)
            for i in range(N_UP):
                fn = f"{kind}_up_{i + 1}.wav"
                if params is None:
                    x = synth_lizard(rng, up=True)
                else:
                    x = synth_release(key_variant(params, kind), rng)
                write_wav(os.path.join(pdir, fn), x)
                ups.append(fn)
            keys[kind] = {"down": downs, "up": ups}

        manifest = {
            "id": pid,
            "name": name,
            "brand": brand,
            "type": sw_type,
            "gain": 1.0,
            "keys": keys,
        }
        with open(os.path.join(pdir, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"  {pid}: {N_DOWN * 4 + N_UP * 4} samples")

    # shared mouse clicks
    mdir = os.path.join(out_root, "_mouse")
    os.makedirs(mdir, exist_ok=True)
    rng = np.random.default_rng(1337)
    for mname, mp in MOUSE.items():
        for i in range(2):
            write_wav(os.path.join(mdir, f"{mname}_{i + 1}.wav"),
                      synth_press(mp, rng))
            rp = dict(mp)
            rp["peak"] = 0.5
            write_wav(os.path.join(mdir, f"{mname}_up_{i + 1}.wav"),
                      synth_release(rp, rng))
    with open(os.path.join(mdir, "manifest.json"), "w") as f:
        json.dump({
            "id": "_mouse",
            "buttons": {
                b: {"down": [f"{b}_{i + 1}.wav" for i in range(2)],
                    "up": [f"{b}_up_{i + 1}.wav" for i in range(2)]}
                for b in MOUSE
            },
        }, f, indent=2)
    print("  _mouse: 12 samples")
    print(f"Done → {out_root}")


if __name__ == "__main__":
    main()

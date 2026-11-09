#!/usr/bin/env python3
"""
parse_hpl.py -- Rmax, Rmax/Rpeak, puissance et GFLOPS/W d'un run HPL

Usage :
    python3 parse_hpl.py RUNDIR
    python3 parse_hpl.py --scan $WORK/runs/hpl --csv HPL/results/hpl_runs.csv

Rmax  : colonne Gflops de la ligne "WR..." de la sortie HPL (meilleur resultat si plusieurs).
Valid : la ligne "||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)= ... PASSED".
Rpeak (crete theorique FP64, a citer dans le README) :
  - CPU Grace (Neoverse-V2) : 4 pipelines SIMD 128 bits avec FMA
        = 4 x 2 doubles x 2 flops = 16 flop/cycle/coeur
        Rpeak = coeurs x 16 x frequence  (frequence : GRACE_GHZ, defaut 3.1 GHz -> a verifier avec le probe)
  - GPU H100 du GH200 : 67 TFLOP/s FP64 Tensor Core par GPU (fiche technique NVIDIA)
Puissance : moyenne des echantillons (common/power_sampler.sh) entre t0 et t1 (timing.txt).
"""
import argparse
import csv
import glob
import os
import re
import subprocess
import sys

GRACE_GHZ = float(os.environ.get("GRACE_GHZ", "3.1"))
H100_TF = float(os.environ.get("H100_TF", "67.0"))
HERE = os.path.dirname(os.path.abspath(__file__))


def kv(path):
    return dict(l.strip().split("=", 1) for l in open(path) if "=" in l) if os.path.exists(path) else {}


def power(rundir):
    """puissance moyenne par source via power_summary.py (sortie texte analysee)"""
    pdir = os.path.join(rundir, "power")
    if not os.path.isdir(pdir):
        return {}
    t = kv(os.path.join(rundir, "timing.txt"))
    cmd = [sys.executable, os.path.join(HERE, "..", "..", "common", "power_summary.py"), pdir]
    if "t0" in t:
        cmd += ["--t0", t["t0"], "--t1", t["t1"]]
    txt = subprocess.run(cmd, capture_output=True, text=True).stdout
    return {m.group(1): float(m.group(2)) for m in re.finditer(r"^\s+(\w+)\s*:\s+([\d.]+) W", txt, re.M)}


def analyse(rundir):
    so = os.path.join(rundir, "stdout.txt")
    if not os.path.exists(so):
        return None
    meta = kv(os.path.join(rundir, "meta.txt"))
    text = open(so, errors="replace").read()
    best = None
    # T/V  N  NB  P  Q  Time  Gflops   (Gflops parfois en notation 1.234e+05)
    for m in re.finditer(r"^(W\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.eE+]+)", text, re.M):
        g = float(m.group(7))
        if best is None or g > best["gflops"]:
            best = {"tv": m.group(1), "n": int(m.group(2)), "nb": int(m.group(3)), "p": int(m.group(4)),
                    "q": int(m.group(5)), "time_s": float(m.group(6)), "gflops": g}
    if best is None:
        return None
    nodes = int(meta.get("nodes", 1))
    if meta.get("kind") == "gpu":
        rpeak = 4 * nodes * H100_TF * 1000
    else:
        rpeak = 288 * nodes * 16 * GRACE_GHZ
    pw = power(rundir)
    # source de puissance retenue : superchip complet ("module") si dispo, sinon GPU seul (GPU)
    # ou capteurs Grace (CPU)
    if meta.get("kind") == "gpu":
        src = "module" if "module" in pw else "gpu"
    else:
        src = "hwmon" if "hwmon" in pw else "module"
    ref = pw.get(src)
    return {
        "run": os.path.basename(rundir.rstrip("/")), "kind": meta.get("kind", ""), "tag": meta.get("tag", ""),
        "nodes": nodes, **best, "rpeak_gflops": round(rpeak, 1),
        "rmax_over_rpeak": round(best["gflops"] / rpeak, 4),
        "valid": "yes" if "PASSED" in text else "NO",
        "power_w": round(ref, 1) if ref else "", "power_source": src if ref else "",
        "gflops_per_w": round(best["gflops"] / ref, 2) if ref else "",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir", nargs="?")
    ap.add_argument("--scan")
    ap.add_argument("--csv")
    a = ap.parse_args()
    dirs = sorted(glob.glob(os.path.join(a.scan, "*"))) if a.scan else [a.rundir]
    rows = [r for r in (analyse(d) for d in dirs if d and os.path.isdir(d)) if r]
    for r in rows:
        print(f"{r['run']}: Rmax {r['gflops']:.1f} GFLOP/s (N={r['n']} NB={r['nb']} P={r['p']} Q={r['q']}), "
              f"Rmax/Rpeak {100*r['rmax_over_rpeak']:.1f} %, puissance {r['power_w']} W ({r['power_source']}), "
              f"{r['gflops_per_w']} GFLOPS/W, valide={r['valid']}")
    if a.csv and rows:
        os.makedirs(os.path.dirname(os.path.abspath(a.csv)), exist_ok=True)
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print("CSV :", a.csv)


if __name__ == "__main__":
    main()

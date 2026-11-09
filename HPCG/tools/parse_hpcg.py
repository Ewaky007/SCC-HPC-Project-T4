#!/usr/bin/env python3
"""
parse_hpcg.py -- GFLOP/s, validite, duree, puissance et rapport HPCG/HPL

Usage :
    python3 parse_hpcg.py RUNDIR [--hpl-gflops X]
    python3 parse_hpcg.py --scan $WORK/runs/hpcg --csv HPCG/results/hpcg_runs.csv --hpl-gflops X

On cherche dans stdout.txt et dans les fichiers HPCG-Benchmark*.txt la ligne
    "Final Summary::HPCG result is VALID with a GFLOP/s rating of=..."
et la duree du benchmark ("Benchmark Time Summary::Total=...") : un run officiel doit
durer au moins 1800 s ("official" = yes/no).
--hpl-gflops : Rmax HPL de la MEME configuration (meme nombre de noeuds, meme materiel),
               pour le rapport HPCG/HPL demande par le sujet.
"""
import argparse
import csv
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def kv(path):
    return dict(l.strip().split("=", 1) for l in open(path) if "=" in l) if os.path.exists(path) else {}


def analyse(rundir, hpl):
    files = [os.path.join(rundir, "stdout.txt")] + glob.glob(os.path.join(rundir, "**", "HPCG-Benchmark*.txt"),
                                                             recursive=True)
    text = "".join(open(f, errors="replace").read() for f in files if os.path.exists(f))
    m = re.search(r"HPCG result is (VALID|INVALID) with a GFLOP/s rating of[=:]\s*([\d.]+)", text)
    if not m:
        return None
    t = re.search(r"Benchmark Time Summary::Total[=:]\s*([\d.]+)", text)
    meta = kv(os.path.join(rundir, "meta.txt"))
    gf = float(m.group(2))
    dur = float(t.group(1)) if t else 0.0
    # puissance
    pw = {}
    if os.path.isdir(os.path.join(rundir, "power")):
        tt = kv(os.path.join(rundir, "timing.txt"))
        cmd = [sys.executable, os.path.join(HERE, "..", "..", "common", "power_summary.py"),
               os.path.join(rundir, "power")]
        if "t0" in tt:
            cmd += ["--t0", tt["t0"], "--t1", tt["t1"]]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        pw = {k: float(v) for k, v in re.findall(r"^\s+(\w+)\s*:\s+([\d.]+) W", out, re.M)}
    src = ("module" if "module" in pw else "gpu") if meta.get("kind") == "gpu" else ("hwmon" if "hwmon" in pw else "module")
    p = pw.get(src)
    return {
        "run": os.path.basename(rundir.rstrip("/")), "kind": meta.get("kind", ""), "tag": meta.get("tag", ""),
        "nodes": meta.get("nodes", ""), "np": meta.get("np", ""), "local": meta.get("local", ""),
        "gflops": gf, "valid": "yes" if m.group(1) == "VALID" else "NO",
        "bench_time_s": dur, "official": "yes" if dur >= 1800 else "no",
        "power_w": round(p, 1) if p else "", "power_source": src if p else "",
        "gflops_per_w": round(gf / p, 3) if p else "",
        "hpcg_over_hpl": round(gf / hpl, 4) if hpl else "",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir", nargs="?")
    ap.add_argument("--scan")
    ap.add_argument("--csv")
    ap.add_argument("--hpl-gflops", type=float, default=None)
    a = ap.parse_args()
    dirs = sorted(glob.glob(os.path.join(a.scan, "*"))) if a.scan else [a.rundir]
    rows = [r for r in (analyse(d, a.hpl_gflops) for d in dirs if d and os.path.isdir(d)) if r]
    for r in rows:
        print(f"{r['run']}: {r['gflops']} GFLOP/s valide={r['valid']} duree={r['bench_time_s']} s "
              f"officiel={r['official']} puissance={r['power_w']} W GFLOPS/W={r['gflops_per_w']} "
              f"HPCG/HPL={r['hpcg_over_hpl']}")
    if a.csv and rows:
        os.makedirs(os.path.dirname(os.path.abspath(a.csv)), exist_ok=True)
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print("CSV :", a.csv)


if __name__ == "__main__":
    main()

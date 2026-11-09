#!/usr/bin/env python3
"""
parse_openmx.py -- temps et energie des runs OpenMX

Usage :
    python3 parse_openmx.py RUNDIR
    python3 parse_openmx.py --scan $WORK/runs/openmx --csv OpenMX/results/openmx_runs.csv

On lit dans le fichier <System.Name>.out :
  - "Utot."                     : energie totale (Hartree) -> doit etre identique entre runs
  - "Total Computational Time"  : temps total (s) = metrique de performance (plus petit = mieux)
  - "The SCF was achieved"      : critere de validite (convergence)
"""
import argparse
import csv
import glob
import os
import re


def analyse(rundir):
    meta = {}
    p = os.path.join(rundir, "meta.txt")
    if os.path.exists(p):
        meta = dict(l.strip().split("=", 1) for l in open(p) if "=" in l)
    outs = [f for f in glob.glob(os.path.join(rundir, "*.out"))]
    if not outs:
        return None
    text = open(outs[0], errors="replace").read()
    so = os.path.join(rundir, "stdout.txt")
    full = text + (open(so, errors="replace").read() if os.path.exists(so) else "")
    m = re.search(r"Utot\.\s+(-?\d+\.\d+)", text)
    t = re.search(r"Total Computational Time\s*=\s*([\d.]+)", text)
    return {
        "run": os.path.basename(rundir.rstrip("/")), "tag": meta.get("tag", ""),
        "input": meta.get("input", ""), "build": meta.get("build", ""), "bind": meta.get("bind", ""),
        "nodes": meta.get("nodes", ""), "np": meta.get("np", ""), "nt": meta.get("nt", ""),
        "utot_hartree": m.group(1) if m else "",
        "time_s": t.group(1) if t else "",
        "valid": "yes" if ("The SCF was achieved" in full and t) else "NO",
        "profile": meta.get("profile", "0"),
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
        print(f"{r['run']}: temps {r['time_s']} s, Utot {r['utot_hartree']} Ha, valide={r['valid']}")
    if a.csv and rows:
        os.makedirs(os.path.dirname(os.path.abspath(a.csv)), exist_ok=True)
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print("CSV :", a.csv)


if __name__ == "__main__":
    main()

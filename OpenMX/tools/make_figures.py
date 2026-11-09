#!/usr/bin/env python3
"""
make_figures.py -- figures OpenMX a partir du CSV de parse_openmx.py

Usage :  python3 OpenMX/tools/make_figures.py OpenMX/results/openmx_runs.csv OpenMX/results/
Produit :
  omp_sweep.png   temps NVC sur 4 noeuds en fonction du nombre de threads OpenMP par rang
  scaling.png     speedup / efficacite 1-2-4 noeuds (via common/plot_scaling.py)
  tables.md       tableaux des resultats
"""
import csv
import os
import subprocess
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["valid"] == "yes" and r["profile"] != "1"]
out = sys.argv[2] if len(sys.argv) > 2 else "."
os.makedirs(out, exist_ok=True)
md = ["# OpenMX -- resultats (genere par make_figures.py)\n"]

# --- balayage OpenMP sur 4 noeuds (NVC)
omp = {}
for r in rows:
    if r["input"] == "NVC.dat" and r["nodes"] == "4" and r["build"] == "O3" and r["bind"] == "spread":
        nt = int(r["nt"])
        t = float(r["time_s"])
        omp[nt] = min(t, omp.get(nt, 1e30))
if omp:
    ks = sorted(omp)
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.bar([f"{288 // k}x{k}" for k in ks], [omp[k] for k in ks], color="#3b6ea5")
    ax.set_xlabel("MPI ranks per node x OpenMP threads per rank")
    ax.set_ylabel("Total computational time (s)")
    ax.set_title("OpenMX NVC on 4 Grace nodes (1152 cores)")
    fig.tight_layout()
    fig.savefig(os.path.join(out, "omp_sweep.png"), dpi=150)
    md += ["## NVC, 4 noeuds : threads OpenMP par rang\n", "| rangs/noeud | threads/rang | temps (s) |", "|---|---|---|"]
    md += [f"| {288 // k} | {k} | {omp[k]:.1f} |" for k in ks]
    md.append("")

# --- autres leviers et scalabilite : simple tableau de tous les runs valides
md += ["## Tous les runs valides\n", "| tag | noeuds | rangs | threads | build | placement | temps (s) | Utot (Ha) |",
       "|---|---|---|---|---|---|---|---|"]
for r in sorted(rows, key=lambda r: (r["tag"], int(r["nodes"]), int(r["nt"]))):
    md.append(f"| {r['tag']} | {r['nodes']} | {r['np']} | {r['nt']} | {r['build']} | {r['bind']} | {r['time_s']} | {r['utot_hartree']} |")
open(os.path.join(out, "tables.md"), "w").write("\n".join(md) + "\n")

# --- scalabilite : on prend les runs NVC du meilleur NT (tags scaling + omp)
sc = [r for r in rows if r["input"] == "NVC.dat" and r["tag"] in ("scaling", "omp") and r["build"] == "O3"]
if sc:
    best_nt = min(omp, key=omp.get) if omp else int(sc[0]["nt"])
    path = os.path.join(out, "scaling_data.csv")
    with open(path, "w") as f:
        f.write("nodes,time_s\n")
        for r in sc:
            if int(r["nt"]) == best_nt:
                f.write(f"{r['nodes']},{r['time_s']}\n")
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run([sys.executable, os.path.join(here, "..", "..", "common", "plot_scaling.py"), path,
                    "--x", "nodes", "--y", "time_s", "--kind", "time",
                    "--title", f"OpenMX NVC strong scaling ({best_nt} OpenMP threads/rank)",
                    "--out", os.path.join(out, "scaling.png")])
print("\n".join(md))

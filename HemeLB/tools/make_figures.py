#!/usr/bin/env python3
"""
make_figures.py -- toutes les figures et tableaux HemeLB a partir du CSV des runs

Usage :
    python3 HemeLB/tools/parse_hemelb.py --scan $WORK/runs/hemelb --csv HemeLB/results/hemelb_runs.csv
    python3 HemeLB/tools/make_figures.py HemeLB/results/hemelb_runs.csv HemeLB/results/

Produit dans le dossier de sortie :
    scaling_cpu_gpu.png (+ .csv)   speedup et efficacite CPU vs GPU, 1/2/4 noeuds
    effects.png                    4 panneaux : rangs MPI, monitoring, vectorisation, frequence d'ecriture
    tables.md                      tous les chiffres sous forme de tableaux (pour le README / poster)
Seuls les runs valides (valid=yes) et sans profilage sont utilises.
"""
import csv
import os
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if r["valid"] != "yes" or r.get("profile", "0") == "1":
                continue
            r["nodes"] = int(r["nodes"])
            r["np"] = int(r["np"])
            r["mlups"] = float(r["mlups"])
            r["mlups_per_worker"] = float(r["mlups_per_worker"])
            r["sim_time_s"] = float(r["sim_time_s"])
            rows.append(r)
    return rows


def best_by(rows, key):
    """garde le meilleur MLUPS pour chaque valeur de key (runs repetes)"""
    out = {}
    for r in rows:
        k = key(r)
        if k not in out or r["mlups"] > out[k]["mlups"]:
            out[k] = r
    return out


def pick(rows, **cond):
    return [r for r in rows if all(r[k] == v for k, v in cond.items())]


def main():
    rows = load(sys.argv[1])
    outdir = sys.argv[2] if len(sys.argv) > 2 else "."
    os.makedirs(outdir, exist_ok=True)
    md = ["# HemeLB -- resultats (genere par make_figures.py)\n"]

    # ---------- 1. scalabilite CPU vs GPU ----------
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 4))
    md.append("## Scalabilite (Aneurysm-VIRTUAL)\n")
    md.append("| mode | noeuds | rangs | MLUPS total | MLUPS/coeur ou /GPU | speedup | efficacite |")
    md.append("|---|---|---|---|---|---|---|")
    for mode, build, color in (("cpu", "cpu-vec", "#3b6ea5"), ("gpu", "gpu", "#c8553d")):
        sel = best_by(pick(rows, tag="scaling", mode=mode, build=build), lambda r: r["nodes"])
        if not sel:
            continue
        ns = sorted(sel)
        ref = sel[ns[0]]["mlups"]
        sp = [sel[n]["mlups"] / ref for n in ns]
        eff = [s / (n / ns[0]) for s, n in zip(sp, ns)]
        a1.plot(ns, [sel[n]["mlups"] for n in ns], "o-", color=color, label=f"{mode.upper()} ({build})")
        a2.plot(ns, [100 * e for e in eff], "o-", color=color, label=mode.upper())
        for n, s, e in zip(ns, sp, eff):
            r = sel[n]
            md.append(f"| {mode} | {n} | {r['np']} | {r['mlups']:.1f} | {r['mlups_per_worker']:.3f} | {s:.2f} | {100*e:.0f} % |")
    a1.set_yscale("log")
    a1.set_ylabel("MLUPS (total)")
    a2.set_ylabel("parallel efficiency (%)")
    a2.axhline(100, ls="--", c="k", lw=1)
    a2.set_ylim(0, 120)
    for ax in (a1, a2):
        ax.set_xscale("log", base=2)
        ax.set_xticks([1, 2, 4])
        ax.set_xticklabels(["1", "2", "4"])
        ax.set_xlabel("nodes (288 Grace cores or 4 H100 per node)")
        ax.grid(alpha=0.3)
        ax.legend()
    fig.suptitle("HemeLB (HemePure) Aneurysm-VIRTUAL on ROMEO GH200 -- strong scaling")
    fig.tight_layout()
    fig.savefig(os.path.join(outdir, "scaling_cpu_gpu.png"), dpi=150)
    md.append("")

    # ---------- 2. effets ----------
    fig, axs = plt.subplots(2, 2, figsize=(11, 8))

    # (a) rangs MPI sur 1 noeud
    ax = axs[0, 0]
    sel = pick(rows, mode="cpu", build="cpu-vec", nodes=1)
    sel = [r for r in sel if r["tag"] in ("ranks", "scaling")]
    byr = best_by(sel, lambda r: r["np"])
    if byr:
        ks = sorted(byr)
        ax.bar([str(k) for k in ks], [byr[k]["mlups"] for k in ks], color="#3b6ea5")
        ax.set_title("(a) CPU, 1 node: MPI ranks")
        ax.set_xlabel("MPI ranks")
        ax.set_ylabel("MLUPS")
        md.append("## Effet du nombre de rangs MPI (CPU, 1 noeud)\n\n| rangs | MLUPS | MLUPS/coeur |\n|---|---|---|")
        md += [f"| {k} | {byr[k]['mlups']:.1f} | {byr[k]['mlups_per_worker']:.3f} |" for k in ks]
        md.append("")

    # (b)(c)(d) comparaisons a deux ou plusieurs series par nombre de noeuds
    def grouped(ax, title, series, ylabel="MLUPS"):
        md.append(f"## {title}\n")
        md.append("| serie | " + " | ".join(f"{n} noeud(s)" for n in (1, 2, 4)) + " |")
        md.append("|---|---|---|---|")
        width = 0.8 / max(1, len(series))
        for i, (label, sub) in enumerate(series):
            b = best_by(sub, lambda r: r["nodes"])
            xs = [n for n in (1, 2, 4)]
            ys = [b[n]["mlups"] if n in b else 0 for n in xs]
            ax.bar([j + i * width for j in range(3)], ys, width, label=label)
            md.append(f"| {label} | " + " | ".join(f"{y:.1f}" if y else "-" for y in ys) + " |")
        ax.set_xticks([j + width * (len(series) - 1) / 2 for j in range(3)])
        ax.set_xticklabels(["1 node", "2 nodes", "4 nodes"])
        ax.set_title(title)
        ax.set_ylabel(ylabel)
        ax.legend(fontsize=8)
        md.append("")

    cpu = pick(rows, mode="cpu")
    grouped(axs[0, 1], "(b) CPU: stability monitoring",
            [("with <monitoring>", pick(cpu, tag="scaling", build="cpu-vec")),
             ("without <monitoring>", pick(cpu, tag="monitoring"))])
    grouped(axs[1, 0], "(c) CPU: vectorisation",
            [("auto-vectorised (-O3)", pick(cpu, tag="scaling", build="cpu-vec")),
             ("-fno-tree-vectorize", pick(cpu, tag="vec", build="cpu-novec"))])
    gpu = pick(rows, mode="gpu")
    grouped(axs[1, 1], "(d) GPU: output frequency",
            [("10x more", pick(gpu, tag="outfreq_x10more")),
             ("reference", pick(gpu, tag="scaling")),
             ("10x less", pick(gpu, tag="outfreq_x10less")),
             ("no output", pick(gpu, tag="outfreq_none"))])
    fig.tight_layout()
    fig.savefig(os.path.join(outdir, "effects.png"), dpi=150)

    # ---------- 3. leviers GPU supplementaires ----------
    ex = best_by(pick(gpu, tag="extra0"), lambda r: r["nodes"])
    ref = best_by(pick(gpu, tag="scaling"), lambda r: r["nodes"])
    if ex:
        md.append("## GPU : 4N+1 rangs (tous les GPU calculent) vs 4N rangs\n\n| noeuds | 4N+1 | 4N |\n|---|---|---|")
        for n in sorted(ex):
            md.append(f"| {n} | {ref[n]['mlups']:.1f} | {ex[n]['mlups']:.1f} |" if n in ref else f"| {n} | - | {ex[n]['mlups']:.1f} |")
        md.append("")
    gp = best_by(pick(gpu, tag="gpus"), lambda r: r["workers"])
    if gp:
        md.append("## GPU : 1, 2, 4 GPU sur un noeud\n\n| GPU | MLUPS | MLUPS/GPU |\n|---|---|---|")
        allg = dict(gp)
        if 1 in ref:
            allg[ref[1]["workers"]] = ref[1]
        for g in sorted(allg):
            md.append(f"| {g} | {allg[g]['mlups']:.1f} | {allg[g]['mlups_per_worker']:.1f} |")
        md.append("")

    with open(os.path.join(outdir, "tables.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    print("\n".join(md))
    print("Figures ->", outdir)


if __name__ == "__main__":
    main()

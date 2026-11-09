#!/usr/bin/env python3
"""
mpiprof_report.py -- synthese des fichiers rank_XXXXX.txt ecrits par libmpiprof.so

Usage :
    python3 common/mpiprof_report.py <dossier_mpiprof> [--title "HemeLB CPU 4 noeuds"] [--out prefix]

Ce que ca produit :
  - le top 3 des appels MPI en NOMBRE d'appels et en TEMPS (somme sur tous les rangs),
  - la meme chose SANS le rang 0 (dans HemeLB, le rang 0 coordonne et ne calcule pas),
  - le % du temps total passe dans MPI, par rang (min / moyenne / max),
  - <prefix>_summary.csv  (une ligne par fonction)  et  <prefix>_summary.md (tableau pour le README/poster)
  - <prefix>_top.png : diagramme en barres (si matplotlib est dispo)
"""
import sys
import os
import glob
import argparse


def read_rank_file(path):
    """Lit un fichier rank_XXXXX.txt -> (rank, host, app_time, {fonction: (appels, temps)})"""
    rank, host, app_time = None, "?", 0.0
    funcs = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "#":
                # "# rank 3 size 16 host romeo-a052 app_time_s 12.3"
                rank = int(parts[2])
                host = parts[6]
                app_time = float(parts[8])
            else:
                funcs[parts[0]] = (int(parts[1]), float(parts[2]))
    return rank, host, app_time, funcs


def aggregate(ranks, skip_rank0=False):
    """Somme appels et temps sur les rangs (en sautant le rang 0 si demande)."""
    total = {}
    for r in ranks:
        if skip_rank0 and r["rank"] == 0:
            continue
        for name, (n, t) in r["funcs"].items():
            n0, t0 = total.get(name, (0, 0.0))
            total[name] = (n0 + n, t0 + t)
    return total


def top3(total, key):
    """key=0 -> trie par nombre d'appels, key=1 -> par temps"""
    return sorted(total.items(), key=lambda kv: kv[1][key], reverse=True)[:3]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--title", default="")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.folder, "rank_*.txt")))
    if not files:
        sys.exit("Aucun fichier rank_*.txt dans " + args.folder)

    ranks = []
    for p in files:
        rank, host, app_time, funcs = read_rank_file(p)
        ranks.append({"rank": rank, "host": host, "app_time": app_time, "funcs": funcs})
    ranks.sort(key=lambda r: r["rank"])
    nranks = len(ranks)
    nhosts = len(set(r["host"] for r in ranks))

    out = args.out or os.path.join(args.folder, "mpiprof")
    lines = []
    lines.append(f"### Profil MPI {args.title}".rstrip())
    lines.append(f"{nranks} rangs MPI sur {nhosts} noeud(s) -- outil : libmpiprof (PMPI)\n")

    for label, skip in (("tous les rangs", False), ("rangs 1..N-1 (sans le rang 0 coordinateur)", True)):
        total = aggregate(ranks, skip_rank0=skip)
        if not total:
            continue
        lines.append(f"**Top 3 -- {label}**\n")
        lines.append("| # | par nombre d'appels | appels | par temps | temps cumule (s) |")
        lines.append("|---|---|---|---|---|")
        by_n, by_t = top3(total, 0), top3(total, 1)
        for i in range(3):
            a = by_n[i] if i < len(by_n) else ("-", (0, 0))
            b = by_t[i] if i < len(by_t) else ("-", (0, 0))
            lines.append(f"| {i+1} | {a[0]} | {a[1][0]:,} | {b[0]} | {b[1][1]:.3f} |")
        lines.append("")

    # part du temps MPI par rang
    frac = []
    for r in ranks:
        t_mpi = sum(t for (_, t) in r["funcs"].values())
        if r["app_time"] > 0:
            frac.append((r["rank"], 100.0 * t_mpi / r["app_time"]))
    if frac:
        vals = [v for (_, v) in frac]
        lines.append(f"Part du temps dans MPI : min {min(vals):.1f} %  /  moyenne {sum(vals)/len(vals):.1f} %"
                     f"  /  max {max(vals):.1f} %  (rang 0 : {frac[0][1]:.1f} %)\n")

    text = "\n".join(lines)
    print(text)
    with open(out + "_summary.md", "w") as f:
        f.write(text + "\n")

    # CSV detaille : une ligne par fonction, totaux avec et sans rang 0
    tot_all, tot_no0 = aggregate(ranks), aggregate(ranks, skip_rank0=True)
    with open(out + "_summary.csv", "w") as f:
        f.write("function,calls_all,time_all_s,calls_no_rank0,time_no_rank0_s\n")
        for name in sorted(tot_all, key=lambda k: -tot_all[k][1]):
            n1, t1 = tot_all[name]
            n2, t2 = tot_no0.get(name, (0, 0.0))
            f.write(f"{name},{n1},{t1:.6f},{n2},{t2:.6f}\n")
    # CSV par rang (utile pour montrer que le rang 0 est different)
    with open(out + "_per_rank.csv", "w") as f:
        f.write("rank,host,app_time_s,mpi_time_s,mpi_percent\n")
        for r in ranks:
            t_mpi = sum(t for (_, t) in r["funcs"].values())
            pct = 100.0 * t_mpi / r["app_time"] if r["app_time"] > 0 else 0
            f.write(f"{r['rank']},{r['host']},{r['app_time']:.4f},{t_mpi:.4f},{pct:.2f}\n")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        items = sorted(tot_no0.items(), key=lambda kv: -kv[1][1])[:6] if tot_no0 else []
        if items:
            fig, axes = plt.subplots(1, 2, figsize=(10, 3.5))
            names = [k for k, _ in items]
            axes[0].barh(names[::-1], [v[0] for _, v in items][::-1], color="#3b6ea5")
            axes[0].set_xlabel("number of calls (ranks 1..N-1)")
            axes[1].barh(names[::-1], [v[1] for _, v in items][::-1], color="#c8553d")
            axes[1].set_xlabel("cumulated time (s, ranks 1..N-1)")
            fig.suptitle(f"MPI profile {args.title}")
            fig.tight_layout()
            fig.savefig(out + "_top.png", dpi=150)
            print("Figure :", out + "_top.png")
    except ImportError:
        pass


if __name__ == "__main__":
    main()

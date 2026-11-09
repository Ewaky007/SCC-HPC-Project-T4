#!/usr/bin/env python3
"""
plot_scaling.py -- courbe d'acceleration (speedup) et d'efficacite a partir d'un CSV

Usage :
    python3 common/plot_scaling.py data.csv --x nodes --y time_s --kind time  --title "OpenMX NVC" --out fig.png
    python3 common/plot_scaling.py data.csv --x nodes --y mlups  --kind rate  --group variant --out fig.png

  --kind time : y est un TEMPS (plus petit = mieux)  -> speedup = T(ref) / T(n)
  --kind rate : y est un DEBIT (MLUPS, GFLOP/s...)   -> speedup = R(n) / R(ref)
  Efficacite = speedup / (n / n_ref)     (1.0 = scalabilite parfaite)
  --group     : colonne qui separe plusieurs courbes (ex. cpu/gpu, vec/novec)

Le CSV doit avoir une ligne d'en-tete. Si plusieurs lignes ont le meme x
(runs repetes), on garde la MEILLEURE valeur.
Ecrit aussi <out>.csv avec speedup et efficacite (donnees du poster).
"""
import argparse
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--x", default="nodes")
    ap.add_argument("--y", required=True)
    ap.add_argument("--kind", choices=["time", "rate"], required=True)
    ap.add_argument("--group", default=None)
    ap.add_argument("--title", default="")
    ap.add_argument("--xlabel", default=None)
    ap.add_argument("--out", default="scaling.png")
    a = ap.parse_args()

    # lecture : best[groupe][x] = meilleure valeur
    best = {}
    with open(a.csv) as f:
        for row in csv.DictReader(f):
            try:
                x, y = float(row[a.x]), float(row[a.y])
            except (ValueError, KeyError):
                continue
            g = row.get(a.group, "") if a.group else ""
            cur = best.setdefault(g, {})
            if x not in cur:
                cur[x] = y
            elif a.kind == "time":
                cur[x] = min(cur[x], y)
            else:
                cur[x] = max(cur[x], y)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))
    rows_out = []
    allx = set()
    for g, pts in sorted(best.items()):
        xs = sorted(pts)
        x0, y0 = xs[0], pts[xs[0]]
        sp = [(y0 / pts[x]) if a.kind == "time" else (pts[x] / y0) for x in xs]
        eff = [s / (x / x0) for s, x in zip(sp, xs)]
        label = g if g else None
        ax1.plot(xs, sp, "o-", label=label)
        ax2.plot(xs, [100 * e for e in eff], "o-", label=label)
        allx.update(xs)
        for x, s, e in zip(xs, sp, eff):
            rows_out.append([g, x, pts[x], round(s, 3), round(e, 3)])

    xs = sorted(allx)
    x0 = xs[0]
    ax1.plot(xs, [x / x0 for x in xs], "k--", lw=1, label="ideal")
    ax2.axhline(100, color="k", ls="--", lw=1)
    for ax in (ax1, ax2):
        ax.set_xscale("log", base=2)
        ax.set_xticks(xs)
        ax.set_xticklabels([f"{int(x)}" if x == int(x) else f"{x}" for x in xs])
        ax.set_xlabel(a.xlabel or a.x)
        ax.grid(alpha=0.3)
    ax1.set_ylabel("speedup")
    ax2.set_ylabel("parallel efficiency (%)")
    ax2.set_ylim(0, 120)
    ax1.legend()
    fig.suptitle(a.title)
    fig.tight_layout()
    fig.savefig(a.out, dpi=150)

    with open(a.out.rsplit(".", 1)[0] + ".csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", a.x, a.y, "speedup", "efficiency"])
        w.writerows(rows_out)
    print("Figure :", a.out)
    for r in rows_out:
        print(f"  {r[0] or '-':10s} {a.x}={r[1]:g}  {a.y}={r[2]:g}  speedup={r[3]}  eff={100*r[4]:.0f}%")


if __name__ == "__main__":
    main()

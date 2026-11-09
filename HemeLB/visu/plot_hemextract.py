#!/usr/bin/env python3
"""
plot_hemextract.py -- images + petite video a partir d'une sortie texte de hemeXtract

Chaine complete :
    hemeXtract -X results/Extracted/whole.dat > whole.txt        (binaire HemeLB -> texte)
    python3 plot_hemextract.py whole.txt --out frames/ --plane xz  (texte -> images PNG + MP4)

Format du texte (hemeXtract -X) : des lignes de commentaires "# ...", puis une ligne
d'en-tete du type
    step grid_x grid_y grid_z velocity(0) velocity(1) velocity(2) pressure
puis une ligne par site et par pas de temps ecrit.

Ce que fait le script (simple, numpy + matplotlib) :
  - pour chaque pas de temps ecrit, calcule |v| = sqrt(vx^2+vy^2+vz^2) de chaque site ;
  - projette les sites sur un plan (xy, xz ou yz) en gardant le |v| maximal sur
    l'axe perpendiculaire ("projection d'intensite maximale") -> on voit tout le vaisseau ;
  - sauve une image PNG par pas de temps, puis assemble une video MP4 si ffmpeg existe.
Option --every k : ne garder qu'un site sur k (fichiers enormes).
"""
import argparse
import os
import shutil
import subprocess
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_hemextract(path, every=1):
    """Renvoie (noms_de_colonnes, tableau numpy)"""
    header, skip = None, 0
    with open(path) as f:
        for i, line in enumerate(f):
            if line.startswith("#") or not line.strip():
                continue
            if line.startswith("step"):
                header = line.split()
                skip = i + 1
                break
    if header is None:
        raise SystemExit("En-tete 'step grid_x ...' introuvable : est-ce bien une sortie de hemeXtract -X ?")
    data = np.loadtxt(path, skiprows=skip, comments="#")
    if data.ndim == 1:
        data = data[None, :]
    if every > 1:
        data = data[::every]
    return header, data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("txt")
    ap.add_argument("--out", default="frames")
    ap.add_argument("--plane", default="xz", choices=["xy", "xz", "yz"])
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--field", default="speed", help="speed (|v|) ou pressure")
    ap.add_argument("--fps", type=int, default=6)
    a = ap.parse_args()

    names, d = read_hemextract(a.txt, a.every)
    col = {n: i for i, n in enumerate(names)}
    step = d[:, col["step"]]
    xyz = {"x": d[:, col["grid_x"]], "y": d[:, col["grid_y"]], "z": d[:, col["grid_z"]]}

    if a.field == "pressure":
        val, label = d[:, col["pressure"]], "pressure"
    else:
        v = [c for c in names if c.startswith("velocity")]
        val = np.sqrt(sum(d[:, col[c]] ** 2 for c in v))
        label = "|velocity|"

    h, w = a.plane[0], a.plane[1]
    hi = xyz[h].astype(int) - int(xyz[h].min())
    wi = xyz[w].astype(int) - int(xyz[w].min())
    vmax = np.percentile(val, 99.5) if val.size else 1.0
    os.makedirs(a.out, exist_ok=True)

    steps = np.unique(step)
    print(f"{len(steps)} pas de temps, {d.shape[0]} lignes, champ {label}, plan {a.plane}")
    for k, s in enumerate(steps):
        m = step == s
        img = np.full((wi.max() + 1, hi.max() + 1), np.nan)
        # projection d'intensite maximale : on garde le max sur l'axe non affiche
        np.fmax.at(img, (wi[m], hi[m]), val[m])
        fig, ax = plt.subplots(figsize=(6, 6))
        im = ax.imshow(img, origin="lower", cmap="inferno", vmin=0, vmax=vmax)
        ax.set_title(f"HemeLB Aneurysm -- step {int(s)}")
        ax.set_xlabel(f"grid {h}")
        ax.set_ylabel(f"grid {w}")
        fig.colorbar(im, ax=ax, label=label + " (lattice/SI units as written)")
        fig.tight_layout()
        fig.savefig(os.path.join(a.out, f"frame_{k:04d}.png"), dpi=120)
        plt.close(fig)

    if shutil.which("ffmpeg") and len(steps) > 1:
        mp4 = os.path.join(a.out, "hemelb.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(a.fps),
                        "-i", os.path.join(a.out, "frame_%04d.png"),
                        "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p", mp4], check=False)
        print("Video :", mp4)
    print("Images :", a.out)


if __name__ == "__main__":
    main()

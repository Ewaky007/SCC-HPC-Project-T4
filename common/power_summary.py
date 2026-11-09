#!/usr/bin/env python3
"""
power_summary.py -- puissance moyenne pendant un run, a partir des power_<host>.csv

Usage :
    python3 common/power_summary.py <dossier_power> [--t0 EPOCH --t1 EPOCH] [--gflops X]

  --t0/--t1 : fenetre du calcul (sinon on prend tout l'enregistrement). Les jobs ecrivent
              ces deux instants dans <run>/timing.txt pour exclure le demarrage.
  --gflops  : performance mesuree (Rmax ou HPCG) -> affiche les GFLOPS/W

Sortie : puissance moyenne par source (gpu / module / hwmon) sommee sur tous les GPU/capteurs
         et tous les noeuds, energie (J), et GFLOPS/W.
Convention retenue pour GFLOPS/W (a ecrire dans le README) :
   - "module" si disponible (superchip complet : GPU + Grace + memoire) -> le plus honnete,
   - sinon "gpu" (Hopper seul) en le precisant.
"""
import argparse
import glob
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--t0", type=float, default=None)
    ap.add_argument("--t1", type=float, default=None)
    ap.add_argument("--gflops", type=float, default=None)
    a = ap.parse_args()

    # samples[source][(host, id)] = liste de watts
    samples = {}
    tmin, tmax = None, None
    for path in sorted(glob.glob(os.path.join(a.folder, "power_*.csv"))):
        host = os.path.basename(path)[6:-4]
        with open(path) as f:
            next(f)
            for line in f:
                p = line.strip().split(",")
                if len(p) != 4:
                    continue
                try:
                    t, src, ident, w = float(p[0]), p[1], p[2], float(p[3])
                except ValueError:
                    continue          # "[N/A]" etc.
                if a.t0 is not None and t < a.t0:
                    continue
                if a.t1 is not None and t > a.t1:
                    continue
                samples.setdefault(src, {}).setdefault((host, ident), []).append(w)
                tmin = t if tmin is None else min(tmin, t)
                tmax = t if tmax is None else max(tmax, t)

    if not samples:
        print("Aucun echantillon.")
        return
    duration = (tmax - tmin) if tmin is not None else 0
    print(f"Fenetre analysee : {duration:.1f} s")
    result = {}
    for src, series in samples.items():
        # moyenne de chaque capteur puis somme des capteurs = puissance totale moyenne
        total = sum(sum(v) / len(v) for v in series.values())
        hosts = len(set(h for (h, _) in series))
        result[src] = total
        print(f"  {src:7s}: {total:9.1f} W en moyenne ({len(series)} capteurs, {hosts} noeud(s))"
              f"  -> energie ~ {total * duration / 1000:.1f} kJ")
    if a.gflops:
        for src in ("module", "gpu", "hwmon"):
            if src in result and result[src] > 0:
                print(f"  GFLOPS/W ({src}) = {a.gflops / result[src]:.2f}")


if __name__ == "__main__":
    main()

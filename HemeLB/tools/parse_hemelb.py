#!/usr/bin/env python3
"""
parse_hemelb.py -- extrait la performance (MLUPS) des runs HemePure

Usage :
    python3 parse_hemelb.py RUNDIR                     # un seul run : affiche le resume
    python3 parse_hemelb.py --scan $RUNS/hemelb --csv HemeLB/results/hemelb_runs.csv

Definition (page officielle) :
    MLUPS = millions de mises a jour de sites fluides par seconde
          = (nb de sites fluides) x (nb de pas) / (temps de simulation) / 1e6
  - nb de sites fluides : somme des "fluid sites" par rang dans results/report.txt
  - nb de pas           : "Ran for X steps" dans report.txt
  - temps de simulation : timer "Simulation total" (colonne MAX = rang le plus lent),
                          c'est-a-dire SANS la lecture de la geometrie, la decomposition
                          et les ecritures finales (pre/post-traitement exclus).
  Par coeur / par GPU : on divise par le nombre de rangs qui calculent vraiment
  (rangs avec des sites fluides > 0 ; le rang 0 coordonne et n'en a aucun).
"""
import argparse
import csv
import glob
import os
import re


def read_meta(rundir):
    meta = {}
    p = os.path.join(rundir, "meta.txt")
    if os.path.exists(p):
        for line in open(p):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                meta[k] = v
    return meta


def read_report(path):
    """Renvoie un dict avec sites, steps, timers {nom: (local, min, mean, max)}"""
    out = {"rank_sites": [], "timers": {}}
    section = None
    for line in open(path):
        line = line.rstrip("\n")
        m = re.search(r"Ran for (\d+) steps of an intended (\d+)", line)
        if m:
            out["steps"], out["steps_intended"] = int(m.group(1)), int(m.group(2))
        m = re.search(r"with a (\d+) site geometry", line)
        if m:
            out["geometry_sites"] = int(m.group(1))
        m = re.match(r"rank: (\d+), fluid sites: (\d+)", line)
        if m:
            out["rank_sites"].append((int(m.group(1)), int(m.group(2))))
        if line.startswith("Timing data"):
            section = "timers"
            continue
        if section == "timers":
            if not line.strip() or line.startswith("Build"):
                section = None
                continue
            parts = line.split()
            if parts[:4] == ["Name", "Local", "Min", "Mean"]:
                continue
            try:
                vals = [float(x) for x in parts[-4:]]
                out["timers"][" ".join(parts[:-4])] = vals
            except ValueError:
                pass
        if "unstable" in line or "violated" in line:
            out["unstable"] = True
    return out


def analyse(rundir):
    rep = os.path.join(rundir, "results", "report.txt")
    if not os.path.exists(rep):
        return None
    meta = read_meta(rundir)
    r = read_report(rep)
    sites = sum(s for _, s in r["rank_sites"]) or r.get("geometry_sites", 0)
    workers = sum(1 for _, s in r["rank_sites"] if s > 0)
    steps = r.get("steps", 0)
    sim = r["timers"].get("Simulation total", [0, 0, 0, 0])[3]
    tot = r["timers"].get("Total", [0, 0, 0, 0])[3]
    mlups = sites * steps / sim / 1e6 if sim > 0 else 0.0
    valid = (steps == r.get("steps_intended", -1)) and not r.get("unstable", False)
    return {
        "run": os.path.basename(rundir.rstrip("/")),
        "tag": meta.get("tag", ""), "mode": meta.get("mode", ""), "build": meta.get("build", ""),
        "case": meta.get("case", ""), "xmlopts": meta.get("xmlopts", ""),
        "nodes": int(meta.get("nodes", 0) or 0), "np": int(meta.get("np", 0) or 0),
        "workers": workers, "fluid_sites": sites, "steps": steps,
        "sim_time_s": round(sim, 4), "total_time_s": round(tot, 4),
        "mlups": round(mlups, 2),
        "mlups_per_worker": round(mlups / workers, 3) if workers else 0,
        "valid": "yes" if valid else "NO",
        "profile": meta.get("profile", "0"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir", nargs="?")
    ap.add_argument("--scan", default=None, help="dossier contenant tous les runs")
    ap.add_argument("--csv", default=None)
    a = ap.parse_args()

    dirs = []
    if a.scan:
        dirs = sorted(d for d in glob.glob(os.path.join(a.scan, "*")) if os.path.isdir(d))
    elif a.rundir:
        dirs = [a.rundir]
    rows = [x for x in (analyse(d) for d in dirs) if x]
    if not rows:
        print("aucun report.txt trouve")
        return
    for x in rows:
        unit = "par GPU" if x["mode"] == "gpu" else "par coeur"
        print(f"{x['run']}: {x['mlups']} MLUPS total, {x['mlups_per_worker']} MLUPS {unit} "
              f"({x['workers']} rangs de calcul, {x['fluid_sites']} sites, {x['steps']} pas, "
              f"simulation {x['sim_time_s']} s / total {x['total_time_s']} s) valide={x['valid']}")
    if a.csv:
        os.makedirs(os.path.dirname(os.path.abspath(a.csv)), exist_ok=True)
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print("CSV :", a.csv)


if __name__ == "__main__":
    main()

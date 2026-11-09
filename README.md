# SCC-HPC-Project-T4

Projet de sélection **ISC27 Student Cluster Competition** (URCA, cours CHPS0702), trinôme **T4**, sur le supercalculateur **ROMEO** (nœuds NVIDIA GH200 : 4 × Grace 72 cœurs Neoverse-V2 + 4 × H100 96 Go par nœud, aarch64, InfiniBand 4 × 200 Gb/s).

## Équipe et épreuves

| Épreuve | Type | Responsable | Contributeurs |
|---|---|---|---|
| [HemeLB](HemeLB/README.md) (ISC26) | application GPU | Kévin William ([LeGrandUndead](https://github.com/LeGrandUndead)) | François Fabre, Mathéo Brugnon |
| [OpenMX](OpenMX/README.md) (ISC25) | application CPU | Kévin William | François Fabre, Mathéo Brugnon |
| [HPL](HPL/README.md) | benchmark | François Fabre ([Fitz-V](https://github.com/Fitz-V)) | Mathéo Brugnon, Kévin William |
| [HPCG](HPCG/README.md) (ajouté en plus) | benchmark | Mathéo Brugnon ([Ewaky007](https://github.com/Ewaky007)) | François Fabre, Kévin William |

Journal de bord commun : [JOURNAL.md](JOURNAL.md). Contenu du poster : [poster/poster_content_EN.md](poster/poster_content_EN.md).

## Organisation du dépôt

```
common/                outils partagés par toutes les épreuves
  env_romeo.sh           compte Slurm, dossiers de travail, chargement des modules (load_stack nvhpc|gnu)
  probe_romeo.sh         inventaire d'un nœud GH200 (modules, spack, conteneurs, capteurs de puissance)
  fetch_sources.sh       téléchargements à faire sur le login (sources, boost, conteneur arm64)
  mpiprof/               profileur MPI maison (PMPI, LD_PRELOAD) + mpiprof_report.py (top 3)
  power_sampler.sh       relevé de puissance nvidia-smi / hwmon pendant un run + power_summary.py
  plot_scaling.py        courbes d'accélération et d'efficacité à partir d'un CSV
<Épreuve>/
  README.md              démarche, choix, résultats, analyse
  build/                 compilation reproductible (script + job Slurm)
  jobs/                  jobs Slurm + campaign.sh (soumet toutes les expériences d'une phase)
  tools/                 extraction des métriques -> CSV, figures
  results/               meilleur run uniquement + CSV + figures (ce qui est rendu)
  logs/                  sorties Slurm (non versionnées)
```

Les sources externes, binaires et sorties brutes vont dans `$WORK` (`~/scc_t4` par défaut) et **pas** dans git : `src/`, `bin/`, `build/`, `inputs/`, `runs/`, `containers/`.

## Reproduire

Tous les scripts se lancent **depuis la racine du dépôt**. Les nœuds de login de ROMEO sont x86_64 : la compilation et l'exécution se font toujours sur un nœud `armgpu` (aarch64) via Slurm.

```bash
# 0. inventaire + téléchargements (login)
sbatch -A r260084 common/probe_romeo.sh
bash common/fetch_sources.sh all

# 1. compilations (une par épreuve)
sbatch -A r260084 HemeLB/build/build.slurm
sbatch -A r260084 OpenMX/build/build.slurm
sbatch -A r260084 HPL/build/build.slurm
sbatch -A r260084 HPCG/build/build.slurm

# 2. campagnes : voir le README de chaque épreuve (jobs/campaign.sh <phase>)
# 3. analyse : tools/parse_*.py --scan ... --csv ...  puis  tools/make_figures.py
```

Entrées non téléchargeables automatiquement (pièces jointes des pages officielles ou fournies par l'enseignant) : `Bifurcation-TINY/`, `Aneurysm-VIRTUAL/` → `~/scc_t4/inputs/hemelb/` ; `Methane.dat`, `NVC.dat` → `~/scc_t4/inputs/openmx/` ; `source3.962.tar.gz` → `~/scc_t4/src/`.

## Ordre de lancement conseillé (semaine du 9 novembre)

Les heures GPU sont partagées : chaque phase commence par un test court.

| Jour | HemeLB | OpenMX | HPL | HPCG |
|---|---|---|---|---|
| Lundi | probe, fetch, build, `campaign test` | fetch, build, `campaign test` (Methane) | build, `cpu-test` | build, test 60 s |
| Mardi | `probe` puis `cpu` + `gpu` | `omp` (NVC 4 nœuds) | `gpu-test`, `cpu` | GPU test 60 s |
| Mercredi | `profile`, `best`, visu | `scaling`, `levers`, `profile` | `gpu` (1 et 2 nœuds) | runs officiels 30 min CPU + GPU |
| Jeudi | figures, README, poster | figures, README, OpenMX Viewer | tableau, GFLOPS/W | rapport HPCG/HPL |
| Vendredi | rendu | rendu | rendu | rendu |

## Adaptations à ROMEO (communes)

- Compilateurs Intel → GCC (`-mcpu=neoverse-v2`, ou `-v1` si GCC 11) ; MKL → OpenBLAS / ScaLAPACK / FFTW (spack) ; MPI : HPC-X (pile `nvhpc`) ou OpenMPI 4.1.7 spack (pile `gnu`).
- Les consignes « 4 nœuds CPU » = 4 nœuds ROMEO en n'utilisant que les Grace (288 cœurs/nœud).
- Les comparaisons Iris vs ROMEO (HemeLB) deviennent CPU Grace vs GPU Hopper sur ROMEO.

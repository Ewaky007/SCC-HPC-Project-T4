# OpenMX — trinôme T4

- **Responsables :** Mathéo Brugnon, François Fabre, Kévin William (_à préciser : un seul responsable par épreuve d'après le sujet_)
- **Épreuve :** OpenMX ISC25 (application CPU) — base `DFT_DATA19` du paquet 3.9 + **sources 3.962** (pas la 3.9.9)
- **Cas :** `Methane.dat` (entraînement), **`NVC.dat` sur 4 nœuds CPU** (benchmark)
- **Métrique :** « Total Computational Time » (s), plus petit = meilleur

## 1. Ce que fait le code

OpenMX calcule l'état électronique de matériaux par DFT (bases d'orbitales atomiques localisées). Le cycle SCF répète construction du hamiltonien, diagonalisation (ScaLAPACK/ELPA) et mise à jour de la densité (FFT) jusqu'à convergence. Le parallélisme est hybride : MPI entre rangs, OpenMP dans chaque rang (`-nt`).

## 2. Compilation reproductible

```bash
bash common/fetch_sources.sh openmx          # login : openmx3.9.tar.gz ; déposer source3.962.tar.gz dans ~/scc_t4/src
mkdir -p OpenMX/logs
sbatch -A r260084 OpenMX/build/build.slurm   # nœud ARM -> ~/scc_t4/bin/openmx_O3
sbatch -A r260084 OpenMX/build/build.slurm O2   # variante pour le levier "options compilateur"
```

Le script repart toujours du `makefile` d'origine (`makefile.orig`) et écrit la différence dans `OpenMX/build/makefile.diff`, versionnée. Adaptation Intel/x86 → GNU/ARM :

| Original (page ISC25) | ROMEO | Raison |
|---|---|---|
| `mpicc` (icc) `-O3 -march=core-avx2 -ip -no-prec-div -qopenmp` | `mpicc` (gcc) `-O3 -mcpu=neoverse-v* -fopenmp -fcommon` | options Intel inexistantes ; `-fcommon` car GCC ≥ 10 refuse les globales multiples d'OpenMX |
| `mpif90` (ifort) | `mpif90` (gfortran) `-fallow-argument-mismatch` | les appels MPI d'ELPA ne passent plus avec gfortran ≥ 10 |
| MKL : ScaLAPACK, BLACS, FFTW | `netlib-scalapack`, `openblas`, `fftw` (spack) | pas de MKL sur ARM |
| `ifort … -nofor-main -o openmx` | `$(FC) $(OBJS) $(LIB) -lm -o openmx` | gfortran n'injecte pas de `main` |
| `<emmintrin.h>` (SSE, `Krylov.c`) | `mimic_sse.h` via la macro détectée (`-Dnosse`…) | pas de SSE sur ARM |

## 3. Exécution

```bash
bash OpenMX/jobs/campaign.sh test      # Methane, 1 nœud
bash OpenMX/jobs/campaign.sh omp       # NVC 4 nœuds : 1, 2, 4, 8, 18 threads par rang (288/NT rangs par nœud)
BEST_NT=… bash OpenMX/jobs/campaign.sh scaling   # 1 et 2 nœuds (le 4 nœuds vient de la phase omp)
BEST_NT=… bash OpenMX/jobs/campaign.sh levers    # -O2 vs -O3 ; placement "close" vs "spread"
BEST_NT=… bash OpenMX/jobs/campaign.sh profile   # profil MPI 4 nœuds
```

- `DATA.PATH` est réécrit en chemin absolu dans la copie de l'entrée (le run ne se fait pas dans `work/`).
- Placement : `--map-by ppr:(RPN/4):socket:PE=NT --bind-to core`, `OMP_PLACES=cores`, `OMP_PROC_BIND=close`.
- **Validité :** « The SCF was achieved » + « Total Computational Time » présents ; `Utot` doit être identique (à ~1e-6 Ha près) entre toutes les configurations.

```bash
python3 OpenMX/tools/parse_openmx.py --scan $HOME/scc_t4/runs/openmx --csv OpenMX/results/openmx_runs.csv
python3 OpenMX/tools/make_figures.py OpenMX/results/openmx_runs.csv OpenMX/results/
```

## 4. Résultats

> À remplir après les runs (`results/tables.md`, `results/omp_sweep.png`, `results/scaling.png`).

| Rangs/nœud × threads | Temps NVC 4 nœuds (s) |
|---|---|
| 288 × 1 | _…_ |
| 144 × 2 | _…_ |
| 72 × 4 | _…_ |
| 36 × 8 | _…_ |
| 16 × 18 | _…_ |

Leviers testés : ratio MPI/OpenMP (`omp`), options du compilateur (`flags`), placement (`bind`). Scalabilité 1/2/4 nœuds : `results/scaling.png`.

## 5. Profil MPI (4 nœuds)

`common/mpiprof` préchargé (pile `gnu`). Top 3 en appels et en temps : _à remplir_. Limite : les appels MPI faits depuis le Fortran d'ELPA peuvent ne pas être interceptés par les wrappers C.

## 6. Visualisation

Glisser-déposer `NVC.dat` (ou le `.xyz` / `.cube` produit) dans **OpenMX Viewer** (https://www.openmx-square.org/viewer/), puis enregistrer une courte vidéo de rotation (capture d'écran) → `results/visu/`.

## 7. Fichiers rendus

`results/best/` : entrée, `stdout.txt`, fichier `.out`, `meta.txt`, script Slurm ; CSV, figures et synthèse MPI dans `results/`.

# HPL — trinôme T4

- **Responsable :** François Fabre — **Contributeurs :** Mathéo Brugnon, Kévin William
- **Benchmark :** High Performance Linpack (résolution de Ax = b dense, classement TOP500)
- **À reporter :** Rmax, Rmax/Rpeak, paramètres retenus (N, NB, P, Q), puissance moyenne, GFLOPS/W

## 1. Les paramètres de `HPL.dat` (étape 1)

| Paramètre | Rôle | Choix |
|---|---|---|
| **N** | taille de la matrice ; elle occupe 8·N² octets, le calcul coûte ⅔N³ flops | le plus grand qui tient en mémoire : N = √(fraction × mémoire / 8), arrondi à un multiple de NB |
| **NB** | taille des blocs (granularité de la décomposition et des DGEMM) | CPU : 128–256 ; GPU : 512–1024 |
| **P × Q** | grille de processus, P·Q = nombre de rangs | la plus carrée possible, P ≤ Q |

`HPL/tools/make_hpl_dat.py` génère le fichier à partir de ces choix (les autres lignes sont des valeurs classiques).

## 2. Étape 1 : HPL 2.3 netlib sur CPU Grace

```bash
bash common/fetch_sources.sh hpl               # login : hpl-2.3 + conteneur NVIDIA (arm64)
mkdir -p HPL/logs
sbatch -A r260084 HPL/build/build.slurm        # configure + OpenBLAS séquentiel, GCC -O3 -mcpu=neoverse-v*
bash HPL/jobs/campaign.sh cpu-test             # N=40000, NB=128/192/256 : comprendre l'effet de NB
BEST_NB=… bash HPL/jobs/campaign.sh cpu        # run plus gros sur 1 nœud
```

288 rangs MPI par nœud (1 par cœur), BLAS séquentielle (`OPENBLAS_NUM_THREADS=1`).

## 3. Étape 2 : HPL-NVIDIA (conteneur HPC-Benchmarks) sur GPU, 1 puis 2 nœuds

```bash
bash HPL/jobs/campaign.sh gpu-test             # 1 nœud, petit N : vérifier conteneur + MPI
bash HPL/jobs/campaign.sh gpu                  # 1 nœud NB=576/1024, puis 2 nœuds
```

- Image `nvcr.io/nvidia/hpc-benchmarks:25.04` tirée **en arm64** (`apptainer pull --arch arm64`, le login étant x86).
- 1 rang par GPU ; `hpl.sh --cpu-affinity 0-71:72-143:144-215:216-287 --mem-affinity 0:1:2:3 --gpu-affinity 0:1:2:3`.
- Lancement `srun --mpi=pmix` ; si PMIx n'est pas disponible : `LAUNCH=mpirun`.
- Taille : environ 80 Go de matrice par GPU (`GB_PER_GPU`), dans la plage conseillée par NVIDIA pour Grace Hopper.

## 4. Puissance et efficacité énergétique

`common/power_sampler.sh` tourne sur chaque nœud pendant le run. Il relève `nvidia-smi power.draw` (GPU), `module.power.draw` (superchip complet) si le driver le fournit, et les capteurs hwmon du Grace. La moyenne est faite entre le début et la fin de `xhpl` (`timing.txt`).
**Convention :** GFLOPS/W calculés avec la puissance « module » (GPU + CPU + mémoire) si disponible, sinon GPU seul ; la source est indiquée dans le CSV.

## 5. Rpeak

| Matériel | Calcul | Rpeak |
|---|---|---|
| Grace, 1 nœud | 288 cœurs × 16 flop/cycle (4 pipes 128 bits FMA) × f (3,1 GHz par défaut, à confirmer avec le probe : `GRACE_GHZ`) | ≈ 14,3 TFLOP/s |
| H100 (GH200), 1 GPU | FP64 Tensor Core, fiche NVIDIA (`H100_TF`) | 67 TFLOP/s |
| 1 nœud GPU / 2 nœuds GPU | 4 / 8 × 67 | 268 / 536 TFLOP/s |

## 6. Résultats

```bash
python3 HPL/tools/parse_hpl.py --scan $HOME/scc_t4/runs/hpl --csv HPL/results/hpl_runs.csv
```

| Config | N | NB | P×Q | Rmax (GFLOP/s) | Rmax/Rpeak | Puissance (W) | GFLOPS/W |
|---|---|---|---|---|---|---|---|
| CPU netlib, 1 nœud | _…_ | _…_ | _…_ | _…_ | _…_ | _…_ | _…_ |
| GPU NVIDIA, 1 nœud | _…_ | _…_ | 2×2 | _…_ | _…_ | _…_ | _…_ |
| GPU NVIDIA, 2 nœuds | _…_ | _…_ | 2×4 | _…_ | _…_ | _…_ | _…_ |

Le Rmax GPU 1 et 2 nœuds sert aussi au rapport HPCG/HPL (dossier `HPCG/`).

## 7. Fichiers rendus

`results/best/` : `HPL.dat`, `stdout.txt`, `meta.txt`, CSV de puissance, script Slurm ; `results/hpl_runs.csv`.

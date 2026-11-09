# HPCG — trinôme T4 (épreuve ajoutée en plus)

- **Responsable :** Mathéo Brugnon — **Contributeurs :** François Fabre, Kévin William
- **Benchmark :** HPCG, gradient conjugué préconditionné sur une matrice creuse (problème 3D 27 points)
- **À reporter :** GFLOP/s, rapport HPCG/HPL de la machine, puissance mesurée, explication de l'écart
- Journal détaillé de la compilation : [`JOURNAL-HPCG.md`](JOURNAL-HPCG.md)

## 1. Référence (GitHub hpcg-benchmark) sur CPU Grace

```bash
bash common/fetch_sources.sh hpcg
mkdir -p HPCG/logs
sbatch -A r260084 HPCG/build/build.slurm                          # reprend Make.Grace_MPI_GCC_OMP du journal
sbatch -A r260084 -N 1 -t 00:10:00 --export=ALL,RT=60,TAG=test HPCG/jobs/hpcg_ref.slurm   # réglage
sbatch -A r260084 -N 1 -t 00:45:00 --export=ALL,RT=1800,TAG=official HPCG/jobs/hpcg_ref.slurm
```

## 2. Version optimisée NVIDIA (conteneur HPC-Benchmarks) sur GPU

```bash
sbatch -A r260084 -N 1 -t 00:10:00 --export=ALL,RT=60,TAG=test HPCG/jobs/hpcg_gpu.slurm
sbatch -A r260084 -N 1 -t 00:45:00 --export=ALL,RT=1800,TAG=official HPCG/jobs/hpcg_gpu.slurm
```

Taille locale par GPU `NX×NY×NZ` (256³ par défaut) : l'augmenter tant que la mémoire GPU le permet, sur des runs de 60 s.

## 3. Règle du run officiel

Le run doit durer **au moins 30 minutes** (`RT=1800`). `parse_hpcg.py` indique `official=yes` si la durée mesurée par HPCG dépasse 1800 s, et vérifie la mention `VALID`.

## 4. Résultats

```bash
python3 HPCG/tools/parse_hpcg.py --scan $HOME/scc_t4/runs/hpcg --csv HPCG/results/hpcg_runs.csv --hpl-gflops <Rmax HPL GPU 1 nœud>
```

| Config | GFLOP/s | Durée (s) | Puissance (W) | GFLOPS/W | HPCG / HPL |
|---|---|---|---|---|---|
| Référence CPU, 1 nœud | _…_ | _…_ | _…_ | _…_ | _…_ |
| NVIDIA GPU, 1 nœud | _…_ | _…_ | _…_ | _…_ | _…_ |

## 5. Pourquoi HPCG ≪ HPL

HPL est dominé par des produits de matrices denses (DGEMM) : chaque donnée chargée sert à des dizaines d'opérations, on atteint presque la crête de calcul. HPCG fait surtout des produits matrice creuse × vecteur et un Gauss-Seidel symétrique : environ 2 flops par valeur de 8 octets lue (intensité arithmétique ≈ 0,25 flop/octet). Il est donc **limité par la bande passante mémoire**, pas par les unités de calcul. Le SYMGS ajoute des dépendances qui limitent le parallélisme. Le rapport HPCG/HPL attendu est de l'ordre de 1 à 3 % sur GPU.

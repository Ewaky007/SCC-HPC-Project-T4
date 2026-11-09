# HemeLB (HemePure) — trinôme T4

- **Responsable :** Kévin William — **Contributeurs :** François Fabre, Mathéo Brugnon
- **Épreuve :** HemeLB ISC26 (application GPU), cas officiel **Aneurysm-VIRTUAL**, entraînement sur **Bifurcation**
- **Machine :** ROMEO, nœuds GH200 (`--constraint=armgpu`) : 4 × (Grace 72 cœurs Neoverse-V2 + H100 96 Go) par nœud
- **Métrique :** MLUPS (millions de mises à jour de sites fluides par seconde), au total et par cœur / par GPU

## 1. Ce que fait le code

HemeLB simule l'écoulement sanguin dans une géométrie vasculaire 3D avec la méthode de Boltzmann sur réseau (LBM, réseau D3Q19). Chaque pas de temps met à jour tous les sites fluides (collision + propagation vers les 18 voisins), puis échange les sites de bord avec les rangs voisins (MPI point à point). L'épreuve impose la variante **HemePure** :

| Version | Dépôt | Exécutable |
|---|---|---|
| CPU | `UCL-CCS/HemePure` | `hemepure` |
| GPU (CUDA) | `UCL-CCS/HemePure-GPU`, branche `HIP-CUDA-ROCM_SL` | `hemepure_gpu` |

Les commits exacts utilisés sont notés automatiquement dans `$WORK/bin/hemepure_<variante>.txt` au moment du build.

## 2. Compilation reproductible

```bash
bash common/fetch_sources.sh hemelb             # login : sources + boost 1.83 (les nœuds peuvent ne pas avoir internet)
mkdir -p HemeLB/logs
sbatch -A r260084 HemeLB/build/build.slurm      # nœud ARM : cpu-vec, cpu-novec, hemeXtract, gpu
```

`HemeLB/build/build_hemepure.sh` reconstruit tout à partir de zéro (dossier de build effacé à chaque fois). Les choix et leurs raisons :

| Option | Valeur | Pourquoi |
|---|---|---|
| `HEMELB_INLET_BOUNDARY` / `OUTLET` | `NASHZEROTHORDERPRESSUREIOLET` | imposé : pression en entrée **et** en sortie |
| `HEMELB_WALL_INLET/OUTLET_BOUNDARY` (GPU) | `NASHZEROTHORDERPRESSURESBB` | réglage du script ROMEO de la page officielle (le GPU ne gère que le bounce-back simple) |
| `HEMELB_USE_VELOCITY_WEIGHTS_FILE` | `OFF` | activé par défaut dans la version GPU ; inutile en pression/pression |
| `HEMELB_USE_SSE3`, `HEMELB_USE_AVX2` | `OFF` | intrinsèques x86 : n'existent pas sur ARM (`-msse3` ferait échouer GCC aarch64) |
| Optimisation CPU | `-O3 -mcpu=neoverse-v2` (ou `-v1` si GCC 11 ne connaît pas V2) | le script teste l'option acceptée |
| Variante « sans vectorisation » | `-O3 … -fno-tree-vectorize` | remplace la comparaison SSE3/AVX2 de la consigne Iris |
| GPU | `HEMELB_GPU_BACKEND=CUDA`, `CMAKE_CUDA_ARCHITECTURES=90`, `HEMELB_CUDA_AWARE_MPI=ON` | Hopper = sm_90 ; HPC-X est CUDA-aware |
| MPI | HPC-X (module `nvhpc/nvhpc-hpcx-cuda12/24.11`), GCC derrière `mpicc`/`mpicxx` | même MPI pour CPU et GPU |

> **Erreur rencontrée au début :** la première tentative clonait `hemelb-emulator/hemelb` (HemeLB « complet ») et échouait sur `Could NOT find TinyXML`. HemePure embarque TinyXML, ParMETIS et ctemplate dans `dep/` : le problème disparaît avec le bon dépôt.

## 3. Exécution

Un seul script Slurm sert à tous les runs, `HemeLB/jobs/run_hemelb.slurm`, piloté par des variables (`MODE`, `BUILD`, `RPN`, `XMLOPTS`, `STEPS`, `PROFILE`, `TAG`). Toutes les expériences sont soumises par phase :

```bash
bash HemeLB/jobs/campaign.sh test      # Bifurcation CPU + GPU (vérifier la chaîne)
bash HemeLB/jobs/campaign.sh probe     # Aneurysm-VIRTUAL, 200 pas : temps par pas
bash HemeLB/jobs/campaign.sh cpu       # scalabilité, rangs MPI, monitoring, vectorisation
bash HemeLB/jobs/campaign.sh gpu       # scalabilité, fréquence d'écriture, placement
bash HemeLB/jobs/campaign.sh profile   # profils MPI 4 et 2 nœuds, CPU et GPU
bash HemeLB/jobs/campaign.sh best      # meilleur run, pas officiels
```

- **CPU :** 1 rang MPI par cœur, répartis également sur les 4 Grace (`--map-by ppr:72:socket --bind-to core`).
- **GPU :** 1 rang par GPU. Dans HemePure-GPU, **le rang 0 ne calcule pas** (il coordonne) et le rang *r* prend le GPU `(r-1) % 4` (`SimulationMaster.cu`). On lance donc **4N+1 rangs** (le 1er nœud reçoit 5 rangs) pour que les 4N GPU calculent, et `gpu_bind.sh` épingle chaque rang sur les 72 cœurs du Grace collé à son GPU. La variante `EXTRA=0` (4N rangs, un GPU inactif) sert de point de comparaison.
- HemePure refuse de démarrer si le dossier `results/` existe : chaque run a son propre dossier `$RUNS/hemelb/<tag>_<mode>_<build>_N<n>_np<np>_<jobid>/`.
- **Validité** (écrite dans `status.txt`) : `report.txt` existe, « Ran for X steps of an intended X », aucune ligne `unstable` / `violated`.

## 4. Mesure de la performance

`HemeLB/tools/parse_hemelb.py` lit `results/report.txt` :

MLUPS = Σ(sites fluides des rangs) × pas / temps du timer **« Simulation total »** (colonne MAX) / 10⁶

Le timer « Simulation total » exclut la lecture de la géométrie, la décomposition et les écritures finales, donc pré- et post-traitement sont exclus comme demandé. « Par cœur / par GPU » = divisé par le nombre de rangs qui ont des sites fluides (le rang 0 n'en a pas).

```bash
python3 HemeLB/tools/parse_hemelb.py --scan $HOME/scc_t4/runs/hemelb --csv HemeLB/results/hemelb_runs.csv
python3 HemeLB/tools/make_figures.py HemeLB/results/hemelb_runs.csv HemeLB/results/
```

## 5. Résultats

> À remplir après les runs (les tableaux sont générés dans `results/tables.md`).

| | Meilleure configuration | MLUPS total | MLUPS / unité |
|---|---|---|---|
| CPU Grace | _N nœuds, 288 rangs/nœud, -O3_ | _…_ | _… /cœur_ |
| GPU Hopper | _N nœuds, 4N+1 rangs_ | _…_ | _… /GPU_ |

Figures : `results/scaling_cpu_gpu.png` (scalabilité CPU vs GPU), `results/effects.png` (rangs MPI, monitoring, vectorisation, fréquence d'écriture).

### Leviers d'optimisation testés (consigne commune n°3)

| Levier | Expérience (`TAG`) | Effet mesuré |
|---|---|---|
| Compilateur / vectorisation | `vec` : `-O3` vs `-fno-tree-vectorize` | _…_ |
| Répartition MPI (CPU) | `ranks` : 36 / 72 / 144 / 288 rangs sur 1 nœud | _…_ |
| Placement MPI/GPU | `extra0` : 4N rangs vs 4N+1 rangs | _…_ |
| Paramètre du code : monitoring | `monitoring` : section `<monitoring>` supprimée | _…_ |
| Paramètre du code : sorties | `outfreq_*` : `period` × 0,1 / × 10 / aucune | _…_ |

### Analyse attendue (à compléter avec les chiffres)

- **Monitoring de stabilité :** `<incompressibility/>` ajoute une réduction globale de contrôle ; l'écart avec/sans montre son coût en communications collectives.
- **Fréquence d'écriture :** écrire 10× plus souvent force des copies GPU → CPU et des écritures MPI-IO. Sur GPU, où un pas est très court, l'I/O pèse beaucoup plus que sur CPU.
- **Vectorisation :** sans intrinsèques, le gain dépend de l'auto-vectorisation NEON/SVE de GCC sur la boucle de collision.
- **Scalabilité :** sur GPU, la charge par GPU diminue vite avec le nombre de nœuds ; l'efficacité baisse quand les échanges de halo ne sont plus masqués par le calcul.

## 6. Profil MPI (4 puis 2 nœuds, CPU et GPU)

Outil : `common/mpiprof` (bibliothèque PMPI maison, préchargée avec `LD_PRELOAD`, aucune recompilation). Elle compte les appels et mesure le temps de chaque fonction MPI, rang par rang. `mpiprof_report.py` sort le top 3 **avec et sans le rang 0**, comme le suggère la page (« rank 0 coordinates »).

| Configuration | Top 3 en nombre d'appels | Top 3 en temps | % du temps dans MPI |
|---|---|---|---|
| CPU 4 nœuds | _…_ | _…_ | _…_ |
| CPU 2 nœuds | _…_ | _…_ | _…_ |
| GPU 4 nœuds | _…_ | _…_ | _…_ |
| GPU 2 nœuds | _…_ | _…_ | _…_ |

## 7. Visualisation

```bash
$HOME/scc_t4/bin/hemeXtract -X results/Extracted/<fichier>.dat > out.txt       # binaire -> texte
python3 HemeLB/visu/plot_hemextract.py out.txt --out HemeLB/results/visu --plane xz   # PNG + MP4
```

`plot_hemextract.py` fait une projection d'intensité maximale de |v| pour chaque pas écrit et assemble une vidéo avec ffmpeg. La voie ParaView de la page officielle (`toParaview.sh`, puis Table To Points, puis coloration par `velZ`) reste possible avec le même fichier texte.

## 8. Fichiers rendus (meilleur run uniquement)

`results/best/` : `input.xml`, `run.log` (sortie standard), `report.txt`, `meta.txt`, script Slurm utilisé ; `results/` : CSV et figures ; `results/profile_*` : synthèses MPI. Pas de binaires ni de fichiers `.dat` volumineux.

## 9. Difficulté principale

_Phrase pour le poster :_ porter un code pensé pour x86 (intrinsèques SSE/AVX) et pour des nœuds 1 GPU vers les nœuds GH200 ARM à 4 GPU : désactiver les intrinsèques, choisir les options `-mcpu`, et adapter le nombre de rangs pour que le rang 0 coordinateur ne laisse pas un GPU inactif.

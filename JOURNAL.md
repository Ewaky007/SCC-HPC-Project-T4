# JOURNAL SCC HPC T4

Journal de bord commun, une entrée par semaine : ce qui a été essayé, ce qui a marché ou échoué, avec les versions. Journaux détaillés : [HemeLB/journal_de_bord_hemelb.md](HemeLB/journal_de_bord_hemelb.md), [HPCG/JOURNAL-HPCG.md](HPCG/JOURNAL-HPCG.md).

---

## Semaine du 29/09/2026

### Benchmark HPL — Responsable : François Fabre — Équipe : Mathéo Brugnon / Kévin William

HPL mesure la performance en calcul dense (résolution d'un système linéaire), c'est le classement du TOP500.
- Étape 1 : compiler la référence HPL 2.3 (netlib) sur les CPU Grace, pour comprendre les paramètres N, NB, P et Q du fichier HPL.dat.
- Étape 2 : utiliser la version GPU du conteneur NVIDIA HPC-Benchmarks sur 1 puis 2 nœuds.
- Reporter Rmax, le rapport Rmax/Rpeak, les paramètres retenus et la puissance moyenne mesurée (par exemple avec nvidia-smi), pour calculer des GFLOPS/W.

### HPCG — Mathéo Brugnon
- Environnement : `romeo_load_x64cpu_env` donne x86_64 → remplacé par `romeo_load_armgpu_env` (aarch64).
- MPI : OpenMPI 4.1.7 spack (hash `nkokjyt`, +cuda, UCX, Slurm) ; GCC 11.5.0.
- HPCG référence compilé (`Make.Grace_MPI_GCC_OMP`), binaire `xhpcg` aarch64 OK. Détails : `HPCG/JOURNAL-HPCG.md`.

### HemeLB — Kévin William
- Accès Slurm : `--account` obligatoire ; nœud `romeo-a052` (aarch64) obtenu.
- Pas de module `cmake` → CMake 3.28.3 aarch64 installé dans `~/tools`. Modules NVHPC 24.11 disponibles (`nvhpc-hpcx-cuda12`).
- Première compilation : `Could NOT find TinyXML` (cause trouvée la semaine du 09/11).

---

## Semaine du 09/11/2026

### Commun
- Structure du dépôt : `common/` (environnement, profileur MPI, mesure de puissance, courbes de scalabilité) et, par épreuve, `build/`, `jobs/`, `tools/`, `results/`.
- `common/probe_romeo.sh` (inventaire d'un nœud GH200) et `common/fetch_sources.sh` (le login est x86 : on télécharge sur le login, on compile sur un nœud ARM).
- **Profileur MPI :** aucun outil identifié sur ROMEO → bibliothèque PMPI maison `common/mpiprof` (nombre d'appels + temps par fonction et par rang, chargée par `LD_PRELOAD`). Testée avec OpenMPI sur un programme jouet.
- Mesure de puissance : `common/power_sampler.sh` (nvidia-smi `power.draw`, `module.power.draw` si disponible, hwmon Grace).
- Compte Slurm retenu : `r260084`.

### HemeLB
- **Cause de l'échec TinyXML :** mauvais dépôt (`hemelb-emulator/hemelb`). L'épreuve impose HemePure : `UCL-CCS/HemePure` (CPU) et `UCL-CCS/HemePure-GPU` branche `HIP-CUDA-ROCM_SL` (GPU), qui embarquent leurs dépendances dans `dep/`.
- Lecture du code : `-msse3` ajouté par défaut en CPU (`HEMELB_USE_SSE3=ON`) → désactivé sur ARM ; fichier de poids de vitesse activé par défaut en GPU → `OFF` pour les conditions en pression ; le rang 0 ne calcule pas et le rang *r* utilise le GPU `(r-1)%nGPU` → lancement à 4N+1 rangs.
- Scripts : build CPU (avec/sans vectorisation) et GPU, job générique, campagne complète, MLUPS depuis `report.txt` (timer « Simulation total »), figures, visualisation hemeXtract → PNG/MP4.
- À faire : runs sur ROMEO.

### OpenMX
- Makefile adapté à GCC/ARM (OpenBLAS + netlib-scalapack + FFTW via spack ; `-fcommon`, `-fallow-argument-mismatch`, `mimic_sse.h` au lieu de SSE) ; diff versionné.
- Scripts : Methane, balayage OpenMP NVC 4 nœuds, scalabilité, leviers, profil.
- À faire : récupérer `source3.962.tar.gz`, compiler, runs.

### HPL
- Générateur de `HPL.dat`, build netlib + OpenBLAS, jobs CPU et GPU (conteneur HPC-Benchmarks 25.04 arm64), Rmax/Rpeak et GFLOPS/W.
- À faire : runs.

### HPCG
- Build de référence scripté (reprend le journal), jobs référence et NVIDIA (`hpcg-aarch64.sh`), contrôle de la durée officielle (≥ 1800 s), rapport HPCG/HPL.
- À faire : runs officiels de 30 min.

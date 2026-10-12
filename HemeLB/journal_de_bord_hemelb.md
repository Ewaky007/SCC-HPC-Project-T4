# Journal de bord — HemeLB / HemePure

## Informations générales

- Projet : SCC — Application HemeLB (Simulation LBM Écoulement Sanguin)
- Machine : ROMEO
- Architecture : NVIDIA Grace Hopper GH200 (ARM Neoverse-V2 + GPU Hopper)
- Application : HemeLB / HemePure
- Responsable : Kévin William
- Contributors : Mathéo Brugnon & François Fabre
- Dépôt : SCC-HPC-Project-T4

---

# Phase 0 — Prise en main & Environnement sur ROMEO

## Objectif

Configurer l'environnement de calcul sur le supercalculateur ROMEO et résoudre les problèmes d'accès et d'outils de compilation pour puces ARM Grace.

## Récupération du code source

Commande :
```bash
git clone https://github.com/hemelb-emulator/hemelb.git
```

Résultat :
```text
Valide
```

## Résolution des accès Slurm & Allocation mémoire

### Problème rencontré : compte et mémoire non spécifiés
Lors de la tentative d'allocation interactive initiale :
```bash
salloc --constraint=armgpu --nodes=1 --ntasks-per-node=1 --time=01:00:00
```

Résultat :
```text
salloc: error: Account is missing: use option --account=<your_account>
salloc: error: Job submit/allocate failed: Invalid account or account/partition combination specified
```

### Vérification du compte actif
Commande :
```bash
sacctmgr show user kevwill format=User,DefaultAccount,Account
```

Résultat :
```text
      User    Def Acct     Account
---------- ---------- ----------
   kevwill    default
```

### Ajustement du salloc avec compte et mémoire
Commande :
```bash
salloc -A default --constraint=armgpu --mem=32G --nodes=1 --ntasks-per-node=1 --time=01:00:00
```

Résultat :
```bash
salloc: Granted job allocation 741015
salloc: Waiting for resource configuration
salloc: Nodes romeo-a052 are ready for job
```

Vérification sur le nœud d'exécution :
```bash
hostname
uname -m
```

Résultat :
```text
hostname : romeo-a052
uname -m : aarch64
```

---

# Phase 1 — Configuration des Outils et Compilateurs

## Vérification et installation des dépendances

### Recherche des modules CMake et NVHPC
Commande :
```bash
module avail cmake
module avail nvhpc
```

Résultat :
```text
------------------------ /opt/softwares/modulefiles ------------------------
nvhpc/nvhpc-byo-compiler/24.11   nvhpc/nvhpc-hpcx/24.11   nvhpc/nvhpc/24.11
nvhpc/nvhpc-hpcx-cuda12/24.11    nvhpc/nvhpc-nompi/24.11
```

Aucun module `cmake` natif disponible dans l'environnement standard.

### Installation locale de CMake (3.28.3 aarch64)
Commande :
```bash
mkdir -p $HOME/tools && cd $HOME/tools
wget https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-linux-aarch64.tar.gz
tar -zxvf cmake-3.28.3-linux-aarch64.tar.gz
export PATH=$HOME/tools/cmake-3.28.3-linux-aarch64/bin:$PATH
cmake --version
```

Résultat :
```text
cmake version 3.28.3
CMake suite maintained and supported by Kitware (kitware.com/cmake).
```

---

# Phase 2 — Compilation CPU (Baseline ARM Grace)

## Configuration du script Slurm de compilation (`compile_hemelb.sh`)

Commande :
```bash
cat << 'EOF' > compile_hemelb.sh
#!/bin/bash
#SBATCH --job-name=compile_hemelb
#SBATCH --account=default
#SBATCH --constraint=armgpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=00:30:00
#SBATCH --output=compile_%j.log

set -e

module purge
module load nvhpc/nvhpc-hpcx-cuda12/24.11

export PATH=$HOME/tools/cmake-3.28.3-linux-aarch64/bin:$PATH

BUILD_DIR="build_cpu"
INSTALL_DIR="$(pwd)/install_cpu"

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

cd $BUILD_DIR

cmake ../hemelb \
    -DCMAKE_C_COMPILER=mpicc \
    -DCMAKE_CXX_COMPILER=mpicxx \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-mcpu=neoverse-v2 -O3" \
    -DHEMELB_USE_GPU=OFF \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

make -j 16
make install
EOF
```

## Soumission et Analyse des Logs

Commande :
```bash
sbatch compile_hemelb.sh
tail -f compile_741028.log
```

Résultat :
```text
-- Detecting CXX compile features - done
-- Found Git: /usr/bin/git (found version "2.47.3")
-- Found MPI_C: /gpfs/app/2025/manual_install/nvhpc/24.11/Linux_aarch64/24.11/comm_libs/12.6/hpcx/hpcx-2.20/ompi/bin/mpicc (found version "3.1")
-- Found MPI_CXX: /gpfs/app/2025/manual_install/nvhpc/24.11/Linux_aarch64/24.11/comm_libs/12.6/hpcx/hpcx-2.20/ompi/bin/mpicxx (found version "3.1")
-- Found MPI: TRUE (found version "3.1")
CMake Error at /usr/share/cmake/Modules/FindPackageHandleStandardArgs.cmake:230 (message):
  Could NOT find TinyXML (missing: TINYXML_INCLUDE_DIR TINYXML_LIBRARIES)
```

## Résolution des Dépendances (TinyXML)

Installation de TinyXML dans le répertoire `$HOME/tools` :
```bash
cd $HOME/tools
git clone https://github.com/cjh/tinyxml.git
cd tinyxml
make
```

Intégration du chemin TinyXML dans `compile_hemelb.sh` via `-DCMAKE_PREFIX_PATH` puis nouvelle compilation.
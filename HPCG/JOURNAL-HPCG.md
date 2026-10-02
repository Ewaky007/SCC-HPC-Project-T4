# Journal de bord — HPCG

## Informations générales

- Projet : SCC — Benchmark HPCG
- Machine : ROMEO
- Architecture : NVIDIA Grace Hopper GH200
- Benchmark : HPCG
- Responsable : Mathéo Brugnon
- Contributors : Kévin William & François Fabre
- Dépôt : SCC-HPC-Project-T4

---

# Phase 1 — Compilation de HPCG référence

## Objectif

Compiler et exécuter la version officielle de référence HPCG
sur les CPU NVIDIA Grace de ROMEO.

## Source utilisée

- HPCG officiel : https://github.com/hpcg-benchmark/hpcg
- Documentation : fichier INSTALL du dépôt HPCG

### Récupération du code source

Commande :
```bash
git clone https://github.com/hpcg-benchmark/hpcg.git
```

Résultat : 
```text
Valide
```


## Environnement

Commande :
```bash
romeo_load_x64cpu_env
```

Résultat :
```text
Architecture : x86_64
MPI          : OpenMPI 5.0.5
MPI arch     : linux-rhel9-zen4
Compilateur  : GCC 11.5.0
```

Ce n'est pas le résultat attendu, sachant que celui étant attendu est : aarch64
Donc, changement de l'environnement.

Commande :
```bash
romeo_load_armgpu_env
```

Lancement pour vérification :
```bash
salloc --account=r260084 --nodes=1 --constraint=armgpu --time=00:30:00 --mem=4G
```

Résultat :
```bash
salloc: Granted job allocation 725496
salloc: Nodes romeo-a057 are ready for job
```

Lancement sur la noeud alloué :
```bash
srun --pty bash
```

Résultat :
```text
hostname : romeo-a057
uname -m : aarch64
```

## Vérification des outils (spécifié dans le INSTALL)

### GCC
Commande :
```bash
which gcc

gcc --version
```

Résultat :
```bash
/usr/bin/gcc

gcc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-5)
Copyright (C) 2021 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

### G++
Commande :
```bash
which g++

g++ --version
```

Résultat :
```bash
/usr/bin/g++

g++ (GCC) 11.5.0 20240719 (Red Hat 11.5.0-5)
Copyright (C) 2021 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

### mpicxx
Commande :
```bash
which mpicxx
```

Résultat :
```bash
Non trouvé : /usr/bin/which: no mpi in (/usr/share/Modules/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/usr/lpp/mmfs/bin)
```

Durant la recherche de mpicxx, l'allocation Slurm a expiré.
Ainsi, j'ai relancé un salloc avec un "time" plus long.

Commande :
```bash
salloc --account=r260084 --nodes=1 --constraint=armgpu --time=04:00:00 --mem=4G

srun --pty bash -l

romeo_load_armgpu_env

spack --version

spack find | grep -Ei "openmpi|mpich"

spack find -lv openmpi

spack load /nkokjyt

which mpicxx
```

Résultat :
```bash
salloc: Pending job allocation 731347
salloc: job 731347 queued and waiting for resources
salloc: job 731347 has been allocated resources
salloc: Granted job allocation 731347
salloc: Waiting for resource configuration
salloc: Nodes romeo-a041 are ready for job

# Chargement de l'environnement
Loading aarch64 (arm, gpus available) environment
Environment loaded. Spack available.

# Version de spack
1.0.1

# les openmpi disponible via spack
openmpi@4.1.7
openmpi@4.1.7
openmpi@4.1.7

# Visualisation détaillée des versions et spécificités à chacuns
-- linux-rhel9-neoverse_v2 / no compilers -----------------------
i6r3tsl openmpi@4.1.7+atomics~cuda~cxx~cxx_exceptions~debug~gpfs~internal-hwloc~internal-libevent~internal-pmix~java~lustre~memchecker~openshmem~orterunprefix+romio+rsh~singularity~static~two_level_namespace+vt+wrapper-rpath build_system=autotools fabrics:=none romio-filesystem:=none schedulers:=none
xvawpow openmpi@4.1.7+atomics~cuda~cxx~cxx_exceptions~debug~gpfs+internal-hwloc~internal-libevent~internal-pmix~java~lustre~memchecker~openshmem~orterunprefix+romio+rsh~singularity~static~two_level_namespace+vt+wrapper-rpath build_system=autotools fabrics:=none romio-filesystem:=none schedulers:=none
nkokjyt openmpi@4.1.7+atomics+cuda~cxx~cxx_exceptions~debug+gpfs~internal-hwloc~internal-libevent~internal-pmix~java+legacylaunchers~lustre~memchecker~openshmem~orterunprefix~pmi+romio+rsh~singularity~static~two_level_namespace+vt+wrapper-rpath build_system=autotools cuda_arch:=90 fabrics:=ucx romio-filesystem:=none schedulers:=slurm
==> 3 installed packages

/

# PATH mpicxx
/apps/2025/spack_install/linux-rhel9-neoverse_v2/linux-rhel9-neoverse_v2/gcc-11.4.1/openmpi-4.1.7-nkokjytvla354jxfvfofjpv2ucrckvdi/bin/mpicxx
```

Ainsi, en chargeant openmpi voici la variante obtenue :

Hash       : nkokjyt
Version    : OpenMPI 4.1.7
CUDA       : activé
GPFS       : activé
Fabric     : UCX
Scheduler  : Slurm
CUDA arch  : 90

Après chargement de la variante OpenMPI `nkokjyt`, le wrapper MPI C++
`mpicxx` devient disponible.

Commande :
```bash
mpicxx --version
```

Résultat :
```bash
g++ (GCC) 11.5.0 20240719 (Red Hat 11.5.0-5)
Copyright (C) 2021 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

## Make file

Le dépôt HPCG fournit plusieurs fichiers de configuration dans le
répertoire `setup/`.

La configuration retenue comme base est :
```text
Make.MPI_GCC_OMP
```

Visualisation :
```bash
cat setup/Make.MPI_GCC_OMP
```

On remarque ici, dans ce makefile, les flags utilisés :
CXX          = mpicxx
CXXFLAGS     = $(HPCG_DEFS) -O3 -ffast-math -ftree-vectorize -ftree-vectorizer-verbose=0 -fopenmp

### Création de copie

Commande :
```bash
cp setup/Make.MPI_GCC_OMP setup/Make.Grace_MPI_GCC_OMP
ls setup/Make.Grace_MPI_GCC_OMP
```

### Configuration du build

Création d'un répertoire de compilation séparé :

```bash
mkdir build_Grace_MPI_GCC_OMP
cd build_Grace_MPI_GCC_OMP

# Cofniguration à partir du fichier d'INSTALL
../configure Grace_MPI_GCC_OMP

# Compilation
make -j4 2>&1 | tee build.log
```

Résultat de la compilation :
```bash
#Compilation réussie
[matheobrugnon@romeo-a041 build_Grace_MPI_GCC_OMP]$ file bin/xhpcg
bin/xhpcg: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, BuildID[sha1]=6d79ee69565d3e0eb86c04199e13fd7d440d4785, for GNU/Linux 3.7.0, with debug_info, not stripped
```

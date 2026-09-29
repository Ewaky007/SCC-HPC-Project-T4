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

## Vérification des outils (spécifié dans le INSTALL) - A faire
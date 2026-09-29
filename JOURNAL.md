# JOURNAL SCC HPC T4


## Benchmark HPL (T1, T3, T4)
### 29/09/2026 - Responsable : François Fabre - Equipe : Mathéo Brugnon / Kévin William

HPL mesure la performance en calcul dense (résolution d'un système linéaire), c'est le classement du TOP500.
•    Étape 1 : compiler la référence HPL 2.3 (netlib) sur les CPU Grace, pour comprendre les paramètres N, NB, P et Q du fichier HPL.dat.
•    Étape 2 : utiliser la version GPU du conteneur NVIDIA HPC-Benchmarks sur 1 puis 2 nœuds.
•    Reporter Rmax, le rapport Rmax/Rpeak, les paramètres retenus et la puissance moyenne mesurée (par exemple avec nvidia-smi), pour calculer des GFLOPS/W.
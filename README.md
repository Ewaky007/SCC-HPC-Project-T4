# SCC-HPC-Project-T4

# Responsables :

## Benchmark HPCG :
- Mathéo Brugnon : https://github.com/Ewaky007
HPCG mesure la performance d'un gradient conjugué creux, plus représentatif des applications réelles que HPL.

## Benchmark HPL :
- François Fabre -> https://github.com/Fitz-V
HPL mesure la performance en calcul dense (résolution d'un système linéaire), c'est le classement du TOP500.

## HemeLB
- Kévin William : https://github.com/LeGrandUndead
Simulation d'écoulement sanguin par Boltzmann sur réseau (variante HemePure, versions CPU et GPU). Compiler avec des conditions aux limites en pression en entrée et en sortie, s'entraîner sur le petit cas Bifurcation, puis traiter le cas Aneurysm-VIRTUAL.

## OpenMX :
- Mathéo Brugnon
- François Fabre
- Kévin William
Simulation de matériaux par la théorie de la fonctionnelle de la densité. Utiliser le paquet 3.9 pour la base de données DFT_DATA19 et les sources 3.962 (pas la 3.9.9). Le Makefile est à adapter à ROMEO. S'entraîner sur le cas Methane.
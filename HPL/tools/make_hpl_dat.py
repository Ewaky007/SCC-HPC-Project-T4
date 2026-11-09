#!/usr/bin/env python3
"""
make_hpl_dat.py -- genere un HPL.dat a partir de quelques choix simples

Usage :
    python3 make_hpl_dat.py --mem-gb 400 --frac 0.8 --nb 256 --p 16 --q 18 > HPL.dat
    python3 make_hpl_dat.py --n 100000 --nb 1024 --p 2 --q 2 > HPL.dat

Les 4 parametres a comprendre (Etape 1 du sujet) :
  N  : taille de la matrice (N x N doubles). La matrice occupe 8*N^2 octets.
       Plus N est grand, plus le calcul (2/3 N^3) domine les communications -> meilleur Rmax,
       mais il faut que la matrice tienne en memoire. On prend N = sqrt(frac * memoire / 8).
  NB : taille des blocs de la decomposition (et des produits matriciels DGEMM).
       Petit (~128-256) sur CPU, grand (~512-1024+) sur GPU.
  P x Q : grille de processus (P lignes, Q colonnes), P*Q = nombre de rangs MPI.
       Grille "presque carree" avec P <= Q en general.
N est arrondi a un multiple de NB (evite un bloc incomplet).
"""
import argparse
import math

TEMPLATE = """HPLinpack benchmark input file
Innovative Computing Laboratory, University of Tennessee
HPL.out      output file name (if any)
6            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
{n}         Ns
1            # of NBs
{nb}          NBs
0            PMAP process mapping (0=Row-,1=Column-major)
1            # of process grids (P x Q)
{p}            Ps
{q}            Qs
16.0         threshold
1            # of panel fact
2            PFACTs (0=left, 1=Crout, 2=Right)
1            # of recursive stopping criterium
4            NBMINs (>= 1)
1            # of panels in recursion
2            NDIVs
1            # of recursive panel fact.
1            RFACTs (0=left, 1=Crout, 2=Right)
1            # of broadcast
1            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)
1            # of lookahead depth
1            DEPTHs (>=0)
2            SWAP (0=bin-exch,1=long,2=mix)
64           swapping threshold
0            L1 in (0=transposed,1=no-transposed) form
0            U  in (0=transposed,1=no-transposed) form
1            Equilibration (0=no,1=yes)
8            memory alignment in double (> 0)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=None)
    ap.add_argument("--mem-gb", type=float, default=None, help="memoire totale utilisable (Go)")
    ap.add_argument("--frac", type=float, default=0.8)
    ap.add_argument("--nb", type=int, required=True)
    ap.add_argument("--p", type=int, required=True)
    ap.add_argument("--q", type=int, required=True)
    a = ap.parse_args()
    n = a.n
    if n is None:
        n = int(math.sqrt(a.frac * a.mem_gb * 1e9 / 8))
    n = (n // a.nb) * a.nb
    print(TEMPLATE.format(n=n, nb=a.nb, p=a.p, q=a.q), end="")


if __name__ == "__main__":
    main()

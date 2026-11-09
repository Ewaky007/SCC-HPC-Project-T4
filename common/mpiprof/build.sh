#!/bin/bash
# Compile libmpiprof.so avec le MPI de la pile choisie.
# IMPORTANT : la lib doit etre compilee avec le MEME MPI que l'application profilee.
#   Pile nvhpc (HemeLB)          :  bash common/mpiprof/build.sh nvhpc
#   Pile gnu  (OpenMX, HPL ref)  :  bash common/mpiprof/build.sh gnu
# A lancer sur un noeud ARM (dans un job ou un salloc).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env_romeo.sh"
stack=${1:-nvhpc}
load_stack $stack
mkdir -p "$WORK/lib"
mpicc -O2 -fPIC -shared -o "$WORK/lib/libmpiprof_${stack}.so" "$HERE/mpiprof.c"
echo "OK : $WORK/lib/libmpiprof_${stack}.so"

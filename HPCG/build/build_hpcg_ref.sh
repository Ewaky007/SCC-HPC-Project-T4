#!/bin/bash
# =====================================================================
# HPCG/build/build_hpcg_ref.sh  --  HPCG reference (GitHub hpcg-benchmark) sur CPU Grace
# =====================================================================
# Reprend exactement la demarche du journal HPCG (JOURNAL-HPCG.md) sous forme de script :
#   pile gnu (OpenMPI 4.1.7 spack, hash nkokjyt) + setup/Make.MPI_GCC_OMP copie en
#   Make.Grace_MPI_GCC_OMP, avec -mcpu adapte a Grace a la place des options x86.
# Usage : sbatch -A r260084 HPCG/build/build.slurm
# =====================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/common/env_romeo.sh"
load_stack gnu
MCPU=""
for c in neoverse-v2 neoverse-v1; do
    echo 'int main(){return 0;}' | g++ -mcpu=$c -x c++ - -o /dev/null 2>/dev/null && { MCPU="-mcpu=$c"; break; }
done
H=$SRC/hpcg
cp "$H/setup/Make.MPI_GCC_OMP" "$H/setup/Make.Grace_MPI_GCC_OMP"
sed -i -E "s|^CXXFLAGS *=.*|CXXFLAGS     = \$(HPCG_DEFS) -O3 $MCPU -ffast-math -ftree-vectorize -fopenmp|" \
    "$H/setup/Make.Grace_MPI_GCC_OMP"
B=$WORK/build/hpcg_ref; rm -rf "$B"; mkdir -p "$B"; cd "$B"
"$H/configure" Grace_MPI_GCC_OMP
make -j "${NJOBS:-16}"
mkdir -p "$WORK/bin"; cp bin/xhpcg "$WORK/bin/xhpcg_ref"
echo "flags=-O3 $MCPU -ffast-math -fopenmp ; commit=$(git -C $H rev-parse HEAD)" > "$WORK/bin/xhpcg_ref.txt"
echo "[hpcg] OK -> $WORK/bin/xhpcg_ref"

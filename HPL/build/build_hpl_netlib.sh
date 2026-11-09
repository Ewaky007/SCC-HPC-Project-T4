#!/bin/bash
# =====================================================================
# HPL/build/build_hpl_netlib.sh  --  Etape 1 : HPL 2.3 (netlib) sur CPU Grace
# =====================================================================
# Usage : sbatch -A r260084 HPL/build/build.slurm   (ou bash ce script sur un noeud ARM)
#
# HPL n'a besoin que de deux choses : MPI et une BLAS (DGEMM, DTRSM...).
#   MPI  : OpenMPI 4.1.7 de spack (pile "gnu")
#   BLAS : OpenBLAS en version SEQUENTIELLE (1 rang MPI = 1 coeur = 1 thread BLAS)
# On utilise le configure d'HPL 2.3 (autotools) plutot qu'un Make.<arch> :
# c'est plus simple a reproduire, il suffit de lui donner la BLAS.
# =====================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/common/env_romeo.sh"
load_stack gnu
spack load openblas 2>/dev/null || echo "[hpl] spack load openblas a echoue (voir probe)"
OB=$(spack location -i openblas 2>/dev/null || echo /usr)

MCPU=""
for c in neoverse-v2 neoverse-v1; do
    echo 'int main(){return 0;}' | gcc -mcpu=$c -x c - -o /dev/null 2>/dev/null && { MCPU="-mcpu=$c"; break; }
done

B=$WORK/build/hpl-2.3
rm -rf "$B" && cp -r "$SRC/hpl-2.3" "$B" && cd "$B"
CC=mpicc CFLAGS="-O3 $MCPU" \
LDFLAGS="-L$OB/lib -L$OB/lib64" LIBS="-lopenblas" \
./configure --prefix="$WORK/hpl-netlib"
make -j "${NJOBS:-16}"
mkdir -p "$WORK/bin"
cp testing/xhpl "$WORK/bin/xhpl_netlib"
echo "flags=-O3 $MCPU ; blas=$OB" > "$WORK/bin/xhpl_netlib.txt"
echo "[hpl] OK -> $WORK/bin/xhpl_netlib"

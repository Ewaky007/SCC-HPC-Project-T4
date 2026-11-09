#!/bin/bash
# =====================================================================
# OpenMX/build/build_openmx.sh  --  compilation reproductible d'OpenMX 3.962 sur Grace
# =====================================================================
# Usage (sur un noeud ARM, via build.slurm) :
#     bash OpenMX/build/build_openmx.sh [O3|O2]      (defaut O3)
#
# Organisation imposee par la page officielle :
#     $SRC/openmx3.9/DFT_DATA19    <- base de pseudo-potentiels du paquet 3.9
#     $SRC/openmx3.9/source3.962   <- sources 3.962 (PAS 3.9.9)
#     $SRC/openmx3.9/work          <- l'executable openmx est installe ici
#
# Adaptation x86/Intel -> ARM/GNU (c'est une partie de l'epreuve) :
#     icc/ifort + -march=core-avx2 -ip -qopenmp   ->  mpicc/mpif90 (GCC) + -mcpu=neoverse-v* -fopenmp
#     MKL (BLAS/LAPACK/ScaLAPACK/BLACS/FFTW)      ->  OpenBLAS + netlib-scalapack + FFTW3 (spack)
#     edition de liens "ifort -nofor-main"         ->  mpif90 (gfortran n'impose pas son main)
#     -fcommon            : GCC >= 10 refuse les variables globales definies plusieurs fois (style C ancien d'OpenMX)
#     -fallow-argument-mismatch : gfortran >= 10 refuse les appels MPI "non types" d'ELPA (Fortran)
#     intrinseques SSE (Krylov.c) : <emmintrin.h> n'existe pas sur ARM ; OpenMX fournit
#        mimic_sse.h, active par une macro que l'on detecte automatiquement ci-dessous.
# =====================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/common/env_romeo.sh"
load_stack gnu
OPT=${1:-O3}
OMX=$SRC/openmx3.9
S=$OMX/source3.962
[ -d "$S" ] || { echo "Sources absentes : $S (voir common/fetch_sources.sh openmx)"; exit 1; }

# --- bibliotheques numeriques via spack (le probe dit lesquelles existent)
for p in openblas netlib-scalapack fftw; do
    spack load $p 2>/dev/null || echo "[openmx] ATTENTION : spack load $p a echoue"
done
loc() { spack location -i "$1" 2>/dev/null || echo "/usr"; }
OPENBLAS=$(loc openblas); SCALAPACK=$(loc netlib-scalapack); FFTW=$(loc fftw)

# --- -mcpu accepte par ce GCC
MCPU=""
for c in neoverse-v2 neoverse-v1; do
    echo 'int main(){return 0;}' | gcc -mcpu=$c -x c - -o /dev/null 2>/dev/null && { MCPU="-mcpu=$c"; break; }
done
case $OPT in O3) OFLAGS="-O3 $MCPU" ;; O2) OFLAGS="-O2" ;; *) OFLAGS="$OPT" ;; esac

# --- macro qui active mimic_sse.h a la place de <emmintrin.h>
SSEDEF=""
guard=$(grep -B3 "#include <emmintrin.h>" "$S/Krylov.c" | grep -oE "#if(n)?def +[A-Za-z_0-9]+" | head -1 || true)
case "$guard" in
  "#ifdef "*)  SSEDEF="-D${guard#\#ifdef }" ;;   # ex. #ifdef nosse -> on definit nosse
  *) SSEDEF="" ;;                                # #ifndef __x86_64__ : rien a faire sur ARM
esac
echo "[openmx] garde SSE trouvee : '${guard:-aucune}' -> $SSEDEF ; flags : $OFLAGS"

INC="-I$FFTW/include -I$OPENBLAS/include"
LIBS="-L$SCALAPACK/lib -L$SCALAPACK/lib64 -lscalapack -L$OPENBLAS/lib -L$OPENBLAS/lib64 -lopenblas \
-L$FFTW/lib -L$FFTW/lib64 -lfftw3 -lgfortran -lmpi_mpifh -lm"

# --- makefile : on part toujours de l'original (makefile.orig) -> build reproductible
cd "$S"
[ -f makefile.orig ] || cp makefile makefile.orig
cp makefile.orig makefile
# remplace les lignes CC=, FC=, LIB= non commentees ; et l'edition de liens par $(FC)
sed -i -E "s|^CC *=.*|CC = mpicc $OFLAGS -fopenmp -fcommon $SSEDEF $INC|" makefile
sed -i -E "s|^FC *=.*|FC = mpif90 $OFLAGS -fopenmp -fallow-argument-mismatch|" makefile
sed -i -E "s|^LIB *=.*|LIB = $LIBS|" makefile
sed -i -E 's|\$\(CC\) +\$\(OBJS\) +\$\(LIB\) +-lm +-o +openmx|$(FC) $(OBJS) $(LIB) -lm -o openmx|' makefile
diff makefile.orig makefile > "$ROOT/OpenMX/build/makefile.diff" || true
echo "[openmx] differences avec l'original -> OpenMX/build/makefile.diff"

make clean >/dev/null 2>&1 || true
make -j "${NJOBS:-16}" all 2>&1 | tail -20
make install
mkdir -p "$WORK/bin"
cp "$OMX/work/openmx" "$WORK/bin/openmx_$OPT"
{ echo "flags=$OFLAGS $SSEDEF"; echo "date=$(date -Is)"; gcc --version | head -1; mpicc --showme 2>/dev/null | head -1; } \
   > "$WORK/bin/openmx_$OPT.txt"
echo "[openmx] OK -> $WORK/bin/openmx_$OPT"

#!/bin/bash
# =====================================================================
# HemeLB/build/build_hemepure.sh  --  compilation reproductible de HemePure
# =====================================================================
# Usage (sur un noeud ARM, via build.slurm) :
#     bash HemeLB/build/build_hemepure.sh cpu-vec     # CPU Grace, auto-vectorisation NEON/SVE
#     bash HemeLB/build/build_hemepure.sh cpu-novec   # CPU Grace, vectorisation desactivee
#     bash HemeLB/build/build_hemepure.sh gpu         # GPU Hopper (CUDA, sm_90)
#     bash HemeLB/build/build_hemepure.sh all
#
# Ce que fait le script, dans l'ordre :
#   1. charge la pile NVHPC (HPC-X = OpenMPI CUDA-aware) avec GCC derriere mpicc/mpicxx ;
#   2. compile les dependances embarquees (dep/ : tinyxml, parmetis, ctemplate, boost headers)
#      UNE SEULE FOIS par depot (dep/install) ;
#   3. compile le code dans un dossier de build separe par variante, a partir de zero ;
#   4. copie l'executable dans $WORK/bin/hemepure_<variante> + note la config dans un .txt.
#
# Choix imposes par l'epreuve :
#   - conditions aux limites en PRESSION en entree et sortie :
#       HEMELB_INLET_BOUNDARY / HEMELB_OUTLET_BOUNDARY = NASHZEROTHORDERPRESSUREIOLET
#   - pas d'intrinseques x86 (SSE3/AVX2 n'existent pas sur ARM) :
#       HEMELB_USE_SSE3=OFF, HEMELB_USE_AVX2=OFF ; on compare a la place
#       -O3 (auto-vectorisation active)  vs  -O3 -fno-tree-vectorize (desactivee).
# =====================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/common/env_romeo.sh"
load_stack nvhpc

variant=${1:-all}
NJOBS=${NJOBS:-32}
mkdir -p "$WORK/bin" "$WORK/build"

# --- quelle option -mcpu accepte le compilateur ?
#     GCC >= 13 connait neoverse-v2 ; GCC 11 (celui du systeme) non -> on retombe sur neoverse-v1
#     (meme famille, SVE 256 bits au lieu de 128 : le code reste correct sur V2).
pick_mcpu() {
    for c in neoverse-v2 neoverse-v1 native; do
        if echo 'int main(){return 0;}' | g++ -mcpu=$c -x c++ - -o /dev/null 2>/dev/null; then
            echo "-mcpu=$c"; return
        fi
    done
    echo ""
}
MCPU=$(pick_mcpu)
echo "[build] g++ = $(g++ --version | head -1) ; option CPU retenue : $MCPU"

# --- dependances (une fois par depot) -------------------------------------------
build_deps() {
    local repo=$1
    if [ -f "$repo/dep/install/lib/libctemplate.a" ] || [ -f "$repo/dep/install/lib64/libctemplate.a" ]; then
        echo "[deps] deja compilees dans $repo/dep/install"
        return
    fi
    echo "[deps] compilation des dependances de $repo"
    rm -rf "$repo/dep/build" && mkdir -p "$repo/dep/build"
    ( cd "$repo/dep/build" && \
      cmake -DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .. && \
      make -j "$NJOBS" )
}

# --- options communes (pression en entree/sortie) --------------------------------
COMMON_OPTS=(
  -DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DHEMELB_USE_GMYPLUS=OFF -DHEMELB_USE_MPI_WIN=OFF
  -DHEMELB_USE_VELOCITY_WEIGHTS_FILE=OFF
  -DHEMELB_INLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET
  -DHEMELB_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSUREIOLET
  -DHEMELB_USE_SSE3=OFF
)

build_cpu() {
    local tag=$1 optflags=$2
    local repo=$SRC/HemePure bdir=$WORK/build/hemelb_$tag
    build_deps "$repo"
    rm -rf "$bdir" && mkdir -p "$bdir"
    cmake -S "$repo/src" -B "$bdir" "${COMMON_OPTS[@]}" \
          -DHEMELB_USE_AVX2=OFF -DHEMELB_USE_AVX512=OFF \
          -DHEMELB_OPTIMISATION="$optflags"
    make -C "$bdir" -j "$NJOBS"
    cp "$bdir/hemepure" "$WORK/bin/hemepure_$tag"
    { echo "variant=$tag"; echo "flags=$optflags"; echo "commit=$(git -C $repo rev-parse HEAD)";
      echo "date=$(date -Is)"; g++ --version | head -1; mpicxx --showme 2>/dev/null | head -1; } \
      > "$WORK/bin/hemepure_$tag.txt"
    echo "[build] OK -> $WORK/bin/hemepure_$tag"
}

build_gpu() {
    local repo=$SRC/HemePure-GPU bdir=$WORK/build/hemelb_gpu
    build_deps "$repo"
    rm -rf "$bdir" && mkdir -p "$bdir"
    # nvcc vient du toolkit CUDA embarque dans NVHPC ; GCC sert de compilateur hote (-ccbin g++)
    local NVCC; NVCC=$(command -v nvcc || ls -d $NVHPC_ROOT/cuda/bin/nvcc 2>/dev/null | head -1)
    cmake -S "$repo/src" -B "$bdir" "${COMMON_OPTS[@]}" \
          -DHEMELB_GPU_BACKEND=CUDA \
          -DCMAKE_CUDA_COMPILER="$NVCC" \
          -DCMAKE_CUDA_ARCHITECTURES=90 \
          -DHEMELB_CUDA_AWARE_MPI=ON \
          -DHEMELB_USE_MPI_PARALLEL_IO=ON \
          -DHEMELB_COMPUTE_ARCHITECTURE=NEUTRAL \
          -DCMAKE_CXX_EXTENSIONS=OFF \
          -DHEMELB_WALL_BOUNDARY=SIMPLEBOUNCEBACK \
          -DHEMELB_WALL_INLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB \
          -DHEMELB_WALL_OUTLET_BOUNDARY=NASHZEROTHORDERPRESSURESBB \
          -DHEMELB_OPTIMISATION="-O3 $MCPU"
    make -C "$bdir" -j "$NJOBS"
    cp "$bdir/hemepure_gpu" "$WORK/bin/hemepure_gpu"
    { echo "variant=gpu"; echo "cuda_arch=90"; echo "commit=$(git -C $repo rev-parse HEAD)";
      echo "date=$(date -Is)"; $NVCC --version | tail -2; } > "$WORK/bin/hemepure_gpu.txt"
    echo "[build] OK -> $WORK/bin/hemepure_gpu"
}

build_hemextract() {
    [ -x "$WORK/bin/hemeXtract" ] && return
    make -C "$SRC/hemeXtract" CXX=g++ && cp "$SRC/hemeXtract/hemeXtract" "$WORK/bin/"
}

case $variant in
  cpu-vec)   build_cpu cpu-vec   "-O3 $MCPU" ;;
  cpu-novec) build_cpu cpu-novec "-O3 $MCPU -fno-tree-vectorize" ;;
  gpu)       build_gpu ;;
  hemextract) build_hemextract ;;
  all)       build_cpu cpu-vec "-O3 $MCPU"
             build_cpu cpu-novec "-O3 $MCPU -fno-tree-vectorize"
             build_hemextract
             build_gpu ;;
  *) echo "variante inconnue : $variant"; exit 1 ;;
esac

# =====================================================================
# common/env_romeo.sh  --  environnement commun a TOUS les scripts T4
# =====================================================================
# Usage :  source common/env_romeo.sh  (depuis la racine du depot)
#
# Pourquoi ce fichier ?
#   Tous les scripts (build + jobs Slurm) chargent le meme environnement :
#   si on change de module ou de compte Slurm, on ne le change qu'ici.
#
# IMPORTANT : sur ROMEO les noeuds de login sont x86_64, les noeuds GH200
# sont aarch64. On compile et on execute TOUJOURS sur un noeud armgpu
# (via sbatch / salloc --constraint=armgpu), jamais sur le login.
# =====================================================================

# --- Compte Slurm du projet (r260084 = compte utilise par l'equipe HPCG).
#     Si ton compte est different : export ACCOUNT=xxx avant de sourcer.
export ACCOUNT=${ACCOUNT:-r260084}

# --- Racine du depot (calculee a partir de l'emplacement de ce fichier)
export T4_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Ou on met les sources externes et les gros fichiers (PAS dans git).
#     Par defaut : $HOME/scc_t4 . Change-le si tu as un espace projet plus grand.
export WORK=${WORK:-$HOME/scc_t4}
export SRC=$WORK/src          # sources telechargees (HemePure, OpenMX, HPL...)
export INPUTS=$WORK/inputs    # cas d'entree (Aneurysm-VIRTUAL, NVC.dat...)
export RUNS=$WORK/runs        # dossiers d'execution (sorties brutes)
export SIF=$WORK/containers   # images apptainer
mkdir -p "$SRC" "$INPUTS" "$RUNS" "$SIF" 2>/dev/null

# --- CMake recent installe a la main (voir HemeLB/journal_de_bord_hemelb.md)
if [ -d "$HOME/tools/cmake-3.28.3-linux-aarch64/bin" ] && [ "$(uname -m)" = "aarch64" ]; then
    export PATH=$HOME/tools/cmake-3.28.3-linux-aarch64/bin:$PATH
fi

# --- Chargement des modules (seulement sur les noeuds ARM)
#     Deux "piles" possibles :
#       nvhpc : compilateurs NVIDIA + HPC-X (OpenMPI CUDA-aware)  -> HemeLB GPU, HemeLB CPU
#       gnu   : GCC systeme + OpenMPI spack                       -> OpenMX, HPL, HPCG ref
load_stack() {
    local stack=${1:-nvhpc}
    if [ "$(uname -m)" != "aarch64" ]; then
        echo "[env] ATTENTION : tu es sur $(hostname) ($(uname -m)), pas sur un noeud GH200."
        echo "[env] Lance ce script via sbatch/salloc --constraint=armgpu."
        return 1
    fi
    module purge 2>/dev/null
    case $stack in
      nvhpc)
        module load nvhpc/nvhpc-hpcx-cuda12/24.11
        # HPC-X fournit mpicc/mpicxx (OpenMPI 4.1, CUDA-aware) ;
        # on garde GCC derriere les wrappers pour le code CPU (meilleur support C++ que nvc++)
        export OMPI_CC=${OMPI_CC:-gcc}
        export OMPI_CXX=${OMPI_CXX:-g++}
        export OMPI_FC=${OMPI_FC:-gfortran}
        ;;
      nvhpc-native)
        # meme pile mais avec les compilateurs NVIDIA (nvc/nvc++/nvfortran) derriere mpicc
        module load nvhpc/nvhpc-hpcx-cuda12/24.11
        unset OMPI_CC OMPI_CXX OMPI_FC
        ;;
      gnu)
        # environnement ROMEO ARM + OpenMPI 4.1.7 (spack, variante cuda+ucx+slurm)
        # cf. HPCG/JOURNAL-HPCG.md : hash nkokjyt
        type romeo_load_armgpu_env >/dev/null 2>&1 && romeo_load_armgpu_env
        spack load /nkokjyt 2>/dev/null || spack load openmpi@4.1.7 2>/dev/null
        ;;
    esac
    echo "[env] pile=$stack  mpicc=$(command -v mpicc)  host=$(hostname)"
}

# --- Petite fonction pour noter l'environnement exact dans chaque sortie de job
log_env() {
    echo "===== ENV $(date -Is) ====="
    echo "host=$(hostname) arch=$(uname -m) job=${SLURM_JOB_ID:-none} nodes=${SLURM_JOB_NODELIST:-none}"
    module list 2>&1 | tail -n +1
    command -v mpicc && mpicc --version 2>&1 | head -1
    command -v mpirun && mpirun --version 2>&1 | head -1
    command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,driver_version,power.limit --format=csv,noheader
    echo "=========================="
}

#!/bin/bash -l
#SBATCH --job-name=hemelb_build
#SBATCH --constraint=armgpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --gpus-per-node=1
#SBATCH --mem=64G
#SBATCH --time=01:00:00
#SBATCH --output=HemeLB/logs/build_%j.out
# ---------------------------------------------------------------------
# Compilation sur un noeud GH200 (aarch64). A soumettre DEPUIS LA RACINE du depot :
#     mkdir -p HemeLB/logs
#     sbatch -A r260084 HemeLB/build/build.slurm            # tout (cpu-vec, cpu-novec, hemeXtract, gpu)
#     sbatch -A r260084 HemeLB/build/build.slurm gpu        # une seule variante
# (--gpus-per-node=1 : pas besoin du GPU pour compiler, mais certaines files
#  armgpu refusent les jobs sans GPU ; on en prend un seul.)
# ---------------------------------------------------------------------
cd "$SLURM_SUBMIT_DIR"
export NJOBS=$SLURM_CPUS_PER_TASK
bash HemeLB/build/build_hemepure.sh "${1:-all}"

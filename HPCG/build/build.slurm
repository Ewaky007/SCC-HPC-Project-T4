#!/bin/bash -l
#SBATCH --job-name=hpcg_build
#SBATCH --constraint=armgpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --mem=32G
#SBATCH --time=00:20:00
#SBATCH --output=HPCG/logs/build_%j.out
# Depuis la racine du depot :  sbatch -A r260084 HPCG/build/build.slurm
cd "$SLURM_SUBMIT_DIR"
export NJOBS=$SLURM_CPUS_PER_TASK
bash HPCG/build/build_hpcg_ref.sh

#!/bin/bash -l
#SBATCH --job-name=openmx_build
#SBATCH --constraint=armgpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --gpus-per-node=1
#SBATCH --mem=64G
#SBATCH --time=00:45:00
#SBATCH --output=OpenMX/logs/build_%j.out
# Depuis la racine du depot :   sbatch -A r260084 OpenMX/build/build.slurm [O3|O2]
cd "$SLURM_SUBMIT_DIR"
export NJOBS=$SLURM_CPUS_PER_TASK
bash OpenMX/build/build_openmx.sh "${1:-O3}"

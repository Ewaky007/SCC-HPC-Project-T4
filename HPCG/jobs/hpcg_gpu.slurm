#!/bin/bash -l
#SBATCH --job-name=hpcg_gpu
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=72
#SBATCH --mem=0
#SBATCH --time=00:45:00
#SBATCH --output=HPCG/logs/%x_%j.out
# =====================================================================
# HPCG/jobs/hpcg_gpu.slurm  --  HPCG-NVIDIA (conteneur HPC-Benchmarks) sur GPU Hopper
#   NX NY NZ  taille locale par GPU (defaut 256 256 256)
#   RT        duree (1800 = officiel ; 60 pour regler)
#   LAUNCH    srun (defaut, --mpi=pmix) ou mpirun
# Exemple test : sbatch -A r260084 -N 1 -t 00:10:00 --export=ALL,RT=60,TAG=test HPCG/jobs/hpcg_gpu.slurm
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
log_env
N=$SLURM_NNODES; NP=$(( 4 * N ))
NX=${NX:-256}; NY=${NY:-256}; NZ=${NZ:-256}; RT=${RT:-1800}; TAG=${TAG:-run}
SIF=${SIF:-$WORK/containers/hpc-benchmarks_25.04.sif}
[ -f "$SIF" ] || apptainer pull "$SIF" docker://nvcr.io/nvidia/hpc-benchmarks:25.04
RUNDIR=$RUNS/hpcg/gpu_${TAG}_N${N}_${NX}x${NY}x${NZ}_rt${RT}_${SLURM_JOB_ID}; mkdir -p "$RUNDIR"; cd "$RUNDIR"
printf "kind=gpu\nnodes=%s\nnp=%s\nlocal=%sx%sx%s\nrt=%s\ntag=%s\njobid=%s\n" $N $NP $NX $NY $NZ $RT $TAG $SLURM_JOB_ID > meta.txt
srun --overlap -N $N --ntasks-per-node=1 --cpus-per-task=1 bash "$SLURM_SUBMIT_DIR/common/power_sampler.sh" power 1 &
PS=$!
ARGS=(--nx $NX --ny $NY --nz $NZ --rt $RT
      --cpu-affinity 0-71:72-143:144-215:216-287 --mem-affinity 0:1:2:3 --gpu-affinity 0:1:2:3)
t0=$(date +%s.%N)
if [ "${LAUNCH:-srun}" = srun ]; then
    srun --overlap -N $N --ntasks-per-node=4 --cpu-bind=none --mpi=pmix \
         apptainer run --nv -B "$RUNDIR:/work" --pwd /work "$SIF" /workspace/hpcg-aarch64.sh "${ARGS[@]}" > stdout.txt 2>&1
else
    load_stack nvhpc
    mpirun -np $NP --map-by ppr:4:node --bind-to none \
         apptainer run --nv -B "$RUNDIR:/work" --pwd /work "$SIF" /workspace/hpcg-aarch64.sh "${ARGS[@]}" > stdout.txt 2>&1
fi
t1=$(date +%s.%N)
kill $PS 2>/dev/null
printf "t0=%s\nt1=%s\n" "$t0" "$t1" > timing.txt
python3 "$SLURM_SUBMIT_DIR/HPCG/tools/parse_hpcg.py" "$RUNDIR"

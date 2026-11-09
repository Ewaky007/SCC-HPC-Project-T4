#!/bin/bash -l
#SBATCH --job-name=hpl_gpu
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=72
#SBATCH --mem=0
#SBATCH --time=00:30:00
#SBATCH --output=HPL/logs/%x_%j.out
# =====================================================================
# HPL/jobs/hpl_gpu.slurm  --  Etape 2 : HPL-NVIDIA (conteneur HPC-Benchmarks) sur GPU Hopper
# =====================================================================
# 1 rang MPI par GPU (4 par noeud), chaque rang epingle sur "son" Grace (72 coeurs)
# et "sa" memoire, via les options --cpu-affinity / --mem-affinity / --gpu-affinity de hpl.sh.
#
#   GB_PER_GPU memoire de matrice par GPU en Go (defaut 80 ; la doc NVIDIA conseille
#              50-90 Gio par GPU sur Grace Hopper, la matrice peut deborder dans la
#              memoire du Grace grace au lien NVLink-C2C)
#   NB         taille de bloc (defaut 1024)
#   N_HPL      force N
#   SIF        image apptainer (defaut $WORK/containers/hpc-benchmarks_25.04.sif)
#   LAUNCH     srun (defaut, --mpi=pmix) ; si pmix absent : LAUNCH=mpirun
#   TAG
# Exemple : sbatch -A r260084 -N 2 --export=ALL,TAG=final HPL/jobs/hpl_gpu.slurm
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
log_env
N=$SLURM_NNODES; NP=$(( 4 * N ))
NB=${NB:-1024}; GB=${GB_PER_GPU:-80}; TAG=${TAG:-run}
SIF=${SIF:-$WORK/containers/hpc-benchmarks_25.04.sif}
[ -f "$SIF" ] || apptainer pull "$SIF" docker://nvcr.io/nvidia/hpc-benchmarks:25.04
P=$(python3 -c "import math;n=$NP;print(max(p for p in range(1,int(math.isqrt(n))+1) if n%p==0))"); Q=$(( NP / P ))
RUNDIR=$RUNS/hpl/gpu_${TAG}_N${N}_nb${NB}_${SLURM_JOB_ID}; mkdir -p "$RUNDIR"; cd "$RUNDIR"
if [ -n "${N_HPL:-}" ]; then ARGS="--n $N_HPL"; else ARGS="--mem-gb $(( GB * NP )) --frac 1.0"; fi
python3 "$SLURM_SUBMIT_DIR/HPL/tools/make_hpl_dat.py" $ARGS --nb $NB --p $P --q $Q > HPL.dat
printf "kind=gpu\nnodes=%s\nnp=%s\nnb=%s\np=%s\nq=%s\ntag=%s\njobid=%s\nsif=%s\n" $N $NP $NB $P $Q $TAG $SLURM_JOB_ID "$SIF" > meta.txt

srun --overlap -N $N --ntasks-per-node=1 --cpus-per-task=1 bash "$SLURM_SUBMIT_DIR/common/power_sampler.sh" power 1 &
PS=$!
AFF=(--cpu-affinity 0-71:72-143:144-215:216-287 --mem-affinity 0:1:2:3 --gpu-affinity 0:1:2:3)
t0=$(date +%s.%N)
if [ "${LAUNCH:-srun}" = srun ]; then
    srun --overlap -N $N --ntasks-per-node=4 --cpu-bind=none --mpi=pmix \
         apptainer run --nv -B "$RUNDIR:/work" "$SIF" \
         /workspace/hpl.sh --dat /work/HPL.dat "${AFF[@]}" > stdout.txt 2>&1
else
    load_stack nvhpc
    mpirun -np $NP --map-by ppr:4:node --bind-to none \
         apptainer run --nv -B "$RUNDIR:/work" "$SIF" \
         /workspace/hpl.sh --dat /work/HPL.dat "${AFF[@]}" > stdout.txt 2>&1
fi
t1=$(date +%s.%N)
kill $PS 2>/dev/null
printf "t0=%s\nt1=%s\n" "$t0" "$t1" > timing.txt
python3 "$SLURM_SUBMIT_DIR/HPL/tools/parse_hpl.py" "$RUNDIR"

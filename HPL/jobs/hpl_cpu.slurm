#!/bin/bash -l
#SBATCH --job-name=hpl_cpu
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=288
#SBATCH --mem=0
#SBATCH --time=01:00:00
#SBATCH --output=HPL/logs/%x_%j.out
# =====================================================================
# HPL/jobs/hpl_cpu.slurm  --  HPL netlib sur les CPU Grace (288 rangs / noeud)
# =====================================================================
#   N_HPL  taille de matrice (defaut : calculee a partir de MEM_GB et FRAC)
#   MEM_GB memoire utilisee par noeud en Go (defaut 120 = 1/4 de la memoire : run court)
#   FRAC   fraction de MEM_GB pour la matrice (defaut 0.8)
#   NB     taille de bloc (defaut 192)
#   TAG    etiquette (nb, grid, final...)
# P x Q = 288*N, grille la plus carree possible (P <= Q).
# Exemple : sbatch -A r260084 -N 1 --export=ALL,NB=256,TAG=nb HPL/jobs/hpl_cpu.slurm
# Duree : netlib + OpenBLAS est lent ; MEM_GB=120 sur 1 noeud -> N~110k, quelques minutes.
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
load_stack gnu
spack load openblas 2>/dev/null
log_env
N=$SLURM_NNODES; NP=$(( 288 * N ))
NB=${NB:-192}; MEM_GB=${MEM_GB:-120}; FRAC=${FRAC:-0.8}; TAG=${TAG:-run}
# grille P x Q la plus carree
P=$(python3 -c "import math;n=$NP;print(max(p for p in range(1,int(math.isqrt(n))+1) if n%p==0))"); Q=$(( NP / P ))
RUNDIR=$RUNS/hpl/cpu_${TAG}_N${N}_nb${NB}_${SLURM_JOB_ID}; mkdir -p "$RUNDIR"; cd "$RUNDIR"
if [ -n "${N_HPL:-}" ]; then ARGS="--n $N_HPL"; else ARGS="--mem-gb $(( MEM_GB * N )) --frac $FRAC"; fi
python3 "$SLURM_SUBMIT_DIR/HPL/tools/make_hpl_dat.py" $ARGS --nb $NB --p $P --q $Q > HPL.dat
printf "kind=cpu\nnodes=%s\nnp=%s\nnb=%s\np=%s\nq=%s\ntag=%s\njobid=%s\n" $N $NP $NB $P $Q $TAG $SLURM_JOB_ID > meta.txt

srun --overlap -N $N --ntasks-per-node=1 --cpus-per-task=1 bash "$SLURM_SUBMIT_DIR/common/power_sampler.sh" power 2 &
PS=$!
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
t0=$(date +%s.%N)
mpirun -np $NP --map-by ppr:72:socket --bind-to core -x PATH -x LD_LIBRARY_PATH \
       -x OPENBLAS_NUM_THREADS -x OMP_NUM_THREADS "$WORK/bin/xhpl_netlib" > stdout.txt 2>&1
t1=$(date +%s.%N)
kill $PS 2>/dev/null
printf "t0=%s\nt1=%s\n" "$t0" "$t1" > timing.txt
python3 "$SLURM_SUBMIT_DIR/HPL/tools/parse_hpl.py" "$RUNDIR"

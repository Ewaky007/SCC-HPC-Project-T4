#!/bin/bash -l
#SBATCH --job-name=hpcg_ref
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=288
#SBATCH --mem=0
#SBATCH --time=00:45:00
#SBATCH --output=HPCG/logs/%x_%j.out
# =====================================================================
# HPCG/jobs/hpcg_ref.slurm  --  HPCG reference sur CPU Grace
#   NX NY NZ  taille locale par rang (defaut 104 104 104)
#   RT        duree demandee en secondes (1800 = run OFFICIEL ; 60 pour regler la taille)
#   RPN       rangs par noeud (defaut 288, 1 thread OpenMP par rang)
#   TAG
# Un run officiel doit durer >= 30 min : RT=1800 et --time >= 00:45:00.
# Exemple test : sbatch -A r260084 -N 1 -t 00:10:00 --export=ALL,RT=60,TAG=test HPCG/jobs/hpcg_ref.slurm
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
load_stack gnu
log_env
N=$SLURM_NNODES; RPN=${RPN:-288}; NP=$(( RPN * N )); TH=$(( 288 / RPN ))
NX=${NX:-104}; NY=${NY:-104}; NZ=${NZ:-104}; RT=${RT:-1800}; TAG=${TAG:-run}
RUNDIR=$RUNS/hpcg/ref_${TAG}_N${N}_np${NP}_${NX}x${NY}x${NZ}_rt${RT}_${SLURM_JOB_ID}; mkdir -p "$RUNDIR"; cd "$RUNDIR"
printf "HPCG benchmark input file\nT4 ROMEO\n%s %s %s\n%s\n" $NX $NY $NZ $RT > hpcg.dat
printf "kind=ref\nnodes=%s\nnp=%s\nthreads=%s\nlocal=%sx%sx%s\nrt=%s\ntag=%s\njobid=%s\n" $N $NP $TH $NX $NY $NZ $RT $TAG $SLURM_JOB_ID > meta.txt
srun --overlap -N $N --ntasks-per-node=1 --cpus-per-task=1 bash "$SLURM_SUBMIT_DIR/common/power_sampler.sh" power 2 &
PS=$!
export OMP_NUM_THREADS=$TH
t0=$(date +%s.%N)
mpirun -np $NP --map-by ppr:$(( RPN / 4 )):socket:PE=$TH --bind-to core -x OMP_NUM_THREADS -x PATH -x LD_LIBRARY_PATH \
       "$WORK/bin/xhpcg_ref" > stdout.txt 2>&1
t1=$(date +%s.%N)
kill $PS 2>/dev/null
printf "t0=%s\nt1=%s\n" "$t0" "$t1" > timing.txt
python3 "$SLURM_SUBMIT_DIR/HPCG/tools/parse_hpcg.py" "$RUNDIR"

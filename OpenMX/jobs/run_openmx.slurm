#!/bin/bash -l
#SBATCH --job-name=openmx
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=288
#SBATCH --mem=0
#SBATCH --time=01:00:00
#SBATCH --output=OpenMX/logs/%x_%j.out
# =====================================================================
# OpenMX/jobs/run_openmx.slurm  --  UN run OpenMX (CPU Grace uniquement)
# =====================================================================
# Noeuds via sbatch -N ; parametres par variables :
#   INPUT   Methane.dat | NVC.dat                (defaut NVC.dat, dans $INPUTS/openmx)
#   NT      threads OpenMP par rang MPI          (defaut 1)
#   BUILD   O3 | O2                               (defaut O3)
#   BIND    spread | close  placement des rangs   (defaut spread : repartis sur les 4 sockets)
#   PROFILE 1 = profil MPI                        (defaut 0)
#   TAG     etiquette (omp, scaling, flags, bind, profile...)
# Le nombre de rangs par noeud est 288 / NT (tous les coeurs Grace sont utilises).
# Exemple :
#   sbatch -A r260084 -N 4 --export=ALL,NT=4,TAG=omp OpenMX/jobs/run_openmx.slurm
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
load_stack gnu
for p in openblas netlib-scalapack fftw; do spack load $p 2>/dev/null; done
log_env

INPUT=${INPUT:-NVC.dat}; NT=${NT:-1}; BUILD=${BUILD:-O3}; BIND=${BIND:-spread}
PROFILE=${PROFILE:-0}; TAG=${TAG:-run}; N=$SLURM_NNODES
RPN=$(( 288 / NT )); NP=$(( RPN * N ))
EXE=$WORK/bin/openmx_$BUILD
[ -x "$EXE" ] || { echo "Executable absent : $EXE"; exit 1; }

RUNDIR=$RUNS/openmx/${TAG}_${INPUT%.dat}_${BUILD}_N${N}_np${NP}_nt${NT}_${BIND}_${SLURM_JOB_ID}
mkdir -p "$RUNDIR"
# copie de l'entree avec DATA.PATH en chemin absolu (le run ne se fait pas dans work/)
sed -E "s|^( *DATA\.PATH).*|\1   $SRC/openmx3.9/DFT_DATA19|" "$INPUTS/openmx/$INPUT" > "$RUNDIR/$INPUT"
grep -q "^ *DATA.PATH" "$RUNDIR/$INPUT" || sed -i "1i DATA.PATH   $SRC/openmx3.9/DFT_DATA19" "$RUNDIR/$INPUT"
cd "$RUNDIR"
printf "input=%s\nnodes=%s\nnp=%s\nnt=%s\nbuild=%s\nbind=%s\nprofile=%s\ntag=%s\njobid=%s\n" \
   "$INPUT" "$N" "$NP" "$NT" "$BUILD" "$BIND" "$PROFILE" "$TAG" "$SLURM_JOB_ID" > meta.txt

PRE=()
if [ "$PROFILE" = 1 ]; then
    export MPIPROF_DIR=$RUNDIR/mpiprof
    LIB=$WORK/lib/libmpiprof_gnu.so
    [ -f "$LIB" ] || bash "$SLURM_SUBMIT_DIR/common/mpiprof/build.sh" gnu
    PRE=(-x LD_PRELOAD=$LIB -x MPIPROF_DIR)
fi

export OMP_NUM_THREADS=$NT OMP_PLACES=cores OMP_PROC_BIND=close
if [ "$BIND" = spread ]; then
    MAP="ppr:$(( RPN / 4 )):socket:PE=$NT"     # rangs repartis sur les 4 Grace
else
    MAP="ppr:${RPN}:node:PE=$NT"               # rangs empiles dans l'ordre des coeurs
fi
t0=$(date +%s.%N)
mpirun -np $NP --map-by $MAP --bind-to core -x OMP_NUM_THREADS -x OMP_PLACES -x OMP_PROC_BIND \
       -x PATH -x LD_LIBRARY_PATH "${PRE[@]}" "$EXE" "$INPUT" -nt $NT > stdout.txt 2>&1
rc=$?
t1=$(date +%s.%N)
printf "t0=%s\nt1=%s\nrc=%s\n" "$t0" "$t1" "$rc" > timing.txt

# validite : SCF converge + fin normale
if grep -q "The SCF was achieved" stdout.txt *.out 2>/dev/null && grep -q "Total Computational Time" *.out 2>/dev/null; then
    echo VALID > status.txt; else echo "INVALID/FAILED rc=$rc" > status.txt; fi
cat status.txt
python3 "$SLURM_SUBMIT_DIR/OpenMX/tools/parse_openmx.py" "$RUNDIR" || true
[ "$PROFILE" = 1 ] && python3 "$SLURM_SUBMIT_DIR/common/mpiprof_report.py" mpiprof --title "OpenMX NVC ${N} nodes" || true
echo "RUNDIR=$RUNDIR"

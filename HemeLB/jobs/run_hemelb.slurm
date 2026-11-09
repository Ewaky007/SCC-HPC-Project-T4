#!/bin/bash -l
#SBATCH --job-name=hemelb
#SBATCH --constraint=armgpu
#SBATCH --exclusive
#SBATCH --gpus-per-node=4
#SBATCH --ntasks-per-node=288
#SBATCH --mem=0
#SBATCH --time=01:00:00
#SBATCH --output=HemeLB/logs/%x_%j.out
# =====================================================================
# HemeLB/jobs/run_hemelb.slurm  --  UN run HemePure (CPU ou GPU)
# =====================================================================
# Le nombre de noeuds se donne a sbatch (-N), le reste par variables :
#
#   MODE    cpu | gpu                         (defaut cpu)
#   BUILD   cpu-vec | cpu-novec | gpu         (defaut cpu-vec, ou gpu si MODE=gpu)
#   CASE    nom du dossier dans $INPUTS/hemelb (defaut Aneurysm-VIRTUAL)
#   RPN     rangs MPI par noeud               (defaut 288 en CPU, 4 en GPU)
#   EXTRA   GPU : 1 = un rang de plus pour le rang 0 coordinateur (4N+1 rangs,
#           les 4N GPU calculent) ; 0 = 4N rangs (un GPU reste inutilise)  (defaut 1)
#   XMLOPTS options pour make_input.py, ex. "--no-monitoring" ou "--output-factor 0.1"
#   STEPS   nombre de pas (tests rapides seulement ; vide = valeur du cas officiel)
#   PROFILE 1 = profilage MPI (libmpiprof)    (defaut 0)
#   TAG     etiquette de l'experience (scaling, ranks, monitoring, vec, outfreq...)
#
# Exemple (depuis la racine du depot) :
#   sbatch -A r260084 -N 2 --export=ALL,MODE=cpu,TAG=scaling HemeLB/jobs/run_hemelb.slurm
# Les sorties vont dans $RUNS/hemelb/<TAG>_<MODE>_<BUILD>_N<n>_np<np>_<jobid>/
# =====================================================================
set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
source common/env_romeo.sh
load_stack nvhpc
log_env

MODE=${MODE:-cpu}
if [ "$MODE" = gpu ]; then BUILD=${BUILD:-gpu}; RPN=${RPN:-4}; else BUILD=${BUILD:-cpu-vec}; RPN=${RPN:-288}; fi
CASE=${CASE:-Aneurysm-VIRTUAL}
EXTRA=${EXTRA:-1}
XMLOPTS=${XMLOPTS:-}
STEPS=${STEPS:-}
PROFILE=${PROFILE:-0}
TAG=${TAG:-run}
N=$SLURM_NNODES

EXE=$WORK/bin/hemepure_$BUILD
[ -x "$EXE" ] || { echo "Executable absent : $EXE (lancer HemeLB/build/build.slurm)"; exit 1; }
CASEDIR=$INPUTS/hemelb/$CASE
[ -f "$CASEDIR/input.xml" ] || { echo "Cas absent : $CASEDIR/input.xml"; exit 1; }

if [ "$MODE" = gpu ]; then NP=$(( RPN * N + EXTRA )); else NP=$(( RPN * N )); fi
RUNDIR=$RUNS/hemelb/${TAG}_${MODE}_${BUILD}_N${N}_np${NP}_${SLURM_JOB_ID}
mkdir -p "$RUNDIR"

# --- preparation du dossier : liens vers les fichiers du cas + input.xml modifie
for f in "$CASEDIR"/*; do [ "$(basename "$f")" != input.xml ] && ln -sf "$f" "$RUNDIR/"; done
opts=$XMLOPTS; [ -n "$STEPS" ] && opts="$opts --steps $STEPS"
python3 HemeLB/tools/make_input.py "$CASEDIR/input.xml" "$RUNDIR/input.xml" $opts
cd "$RUNDIR"

cat > meta.txt <<EOF
mode=$MODE
build=$BUILD
case=$CASE
nodes=$N
np=$NP
rpn=$RPN
extra=$EXTRA
xmlopts=$XMLOPTS
steps_override=$STEPS
profile=$PROFILE
tag=$TAG
jobid=$SLURM_JOB_ID
nodelist=$SLURM_JOB_NODELIST
EOF

# --- profilage MPI (bibliotheque compilee avec le meme MPI : pile nvhpc)
PRELOAD_OPT=()
export MPIPROF_LIB="" MPIPROF_DIR="$RUNDIR/mpiprof"   # vides = pas de profilage
if [ "$PROFILE" = 1 ]; then
    export MPIPROF_DIR=$RUNDIR/mpiprof
    export MPIPROF_LIB=$WORK/lib/libmpiprof_nvhpc.so
    [ -f "$MPIPROF_LIB" ] || bash "$SLURM_SUBMIT_DIR/common/mpiprof/build.sh" nvhpc
    [ "$MODE" = cpu ] && PRELOAD_OPT=(-x LD_PRELOAD=$MPIPROF_LIB -x MPIPROF_DIR)
fi

# --- lancement
t0=$(date +%s.%N)
if [ "$MODE" = cpu ]; then
    # RPN rangs repartis egalement sur les 4 sockets Grace, 1 rang = 1 coeur
    PPS=$(( RPN / 4 ))
    mpirun -np $NP --map-by ppr:${PPS}:socket --bind-to core \
           -x PATH -x LD_LIBRARY_PATH "${PRELOAD_OPT[@]}" \
           "$EXE" -in input.xml -out results > run.log 2>&1
else
    # fichier d'hotes : le 1er noeud recoit RPN+EXTRA rangs (rang 0 coordinateur en plus)
    first=1; : > hostfile
    for h in $(scontrol show hostnames "$SLURM_JOB_NODELIST"); do
        if [ $first = 1 ]; then echo "$h slots=$(( RPN + EXTRA ))" >> hostfile; first=0
        else echo "$h slots=$RPN" >> hostfile; fi
    done
    export NGPU_PER_NODE=4
    mpirun -np $NP --hostfile hostfile --map-by slot --bind-to none \
           -x PATH -x LD_LIBRARY_PATH -x NGPU_PER_NODE -x MPIPROF_LIB -x MPIPROF_DIR \
           bash "$SLURM_SUBMIT_DIR/HemeLB/jobs/gpu_bind.sh" "$EXE" -in input.xml -out results > run.log 2>&1
fi
rc=$?
t1=$(date +%s.%N)
echo "t0=$t0" > timing.txt; echo "t1=$t1" >> timing.txt; echo "rc=$rc" >> timing.txt

# --- verification de validite (critere : le cas va jusqu'au bout et reste stable)
rep=results/report.txt
if [ -f "$rep" ]; then
    ran=$(grep -o "Ran for [0-9]* steps of an intended [0-9]*" "$rep")
    a=$(echo "$ran" | awk '{print $3}'); b=$(echo "$ran" | awk '{print $NF}')
    if [ "$a" = "$b" ] && ! grep -q "unstable\|violated" "$rep"; then echo "VALID ($ran)" > status.txt
    else echo "INVALID ($ran)" > status.txt; fi
else
    echo "FAILED (pas de report.txt, rc=$rc)" > status.txt
fi
cat status.txt
tail -5 run.log
python3 "$SLURM_SUBMIT_DIR/HemeLB/tools/parse_hemelb.py" "$RUNDIR" || true
[ "$PROFILE" = 1 ] && python3 "$SLURM_SUBMIT_DIR/common/mpiprof_report.py" mpiprof \
      --title "HemeLB $MODE ${N} node(s)" || true
echo "RUNDIR=$RUNDIR"

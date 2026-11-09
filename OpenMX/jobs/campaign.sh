#!/bin/bash
# =====================================================================
# OpenMX/jobs/campaign.sh  --  toutes les experiences OpenMX (depuis la racine, sur le login)
#   bash OpenMX/jobs/campaign.sh test      # Methane, 1 noeud (entrainement, quelques minutes)
#   bash OpenMX/jobs/campaign.sh omp       # NVC 4 noeuds : 1,2,4,8,18 threads OpenMP par rang
#   bash OpenMX/jobs/campaign.sh scaling   # NVC 1,2,4 noeuds avec le meilleur NT (BEST_NT=...)
#   bash OpenMX/jobs/campaign.sh levers    # leviers : options compilateur (O2) et placement (close)
#   bash OpenMX/jobs/campaign.sh profile   # profil MPI 4 noeuds
# =====================================================================
set -e
cd "$(dirname "$0")/../.."
source common/env_romeo.sh
mkdir -p OpenMX/logs
J=OpenMX/jobs/run_openmx.slurm
T=${TIME:-01:00:00}
sub() { echo "  job $(sbatch --parsable -A "$ACCOUNT" -N "$1" -t "$2" --export=ALL,$3 $J) : N=$1 $3"; }
B=${BEST_NT:-4}
case ${1:-help} in
  test)    sub 1 00:20:00 "INPUT=Methane.dat,NT=1,TAG=test" ;;
  omp)     for nt in 1 2 4 8 18; do sub 4 $T "NT=$nt,TAG=omp"; done ;;
  scaling) for n in 1 2; do sub $n $T "NT=$B,TAG=scaling"; done
           echo "  (le point 4 noeuds = le meilleur run de la phase omp)";;
  levers)  sub 4 $T "NT=$B,BUILD=O2,TAG=flags"
           sub 4 $T "NT=$B,BIND=close,TAG=bind" ;;
  profile) sub 4 $T "NT=$B,PROFILE=1,TAG=profile" ;;
  *) sed -n 2,9p "$0" ;;
esac

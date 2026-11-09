#!/bin/bash
# =====================================================================
# HPL/jobs/campaign.sh  (depuis la racine, sur le login)
#   bash HPL/jobs/campaign.sh cpu-test   # netlib 1 noeud, petit N, plusieurs NB (comprendre N/NB/P/Q)
#   bash HPL/jobs/campaign.sh cpu        # netlib 1 noeud, meilleur NB, memoire plus grande
#   bash HPL/jobs/campaign.sh gpu-test   # conteneur NVIDIA 1 noeud, petit N (verifier que tout marche)
#   bash HPL/jobs/campaign.sh gpu        # conteneur 1 noeud puis 2 noeuds, plusieurs NB
# =====================================================================
set -e
cd "$(dirname "$0")/../.."
source common/env_romeo.sh
mkdir -p HPL/logs
sub() { echo "  job $(sbatch --parsable -A "$ACCOUNT" -N "$1" -t "$2" --export=ALL,$3 "$4") : N=$1 $3"; }
case ${1:-help} in
  cpu-test) for nb in 128 192 256; do sub 1 00:20:00 "N_HPL=40000,NB=$nb,TAG=nb" HPL/jobs/hpl_cpu.slurm; done ;;
  cpu)      sub 1 01:00:00 "MEM_GB=${MEM_GB:-120},NB=${BEST_NB:-192},TAG=final" HPL/jobs/hpl_cpu.slurm ;;
  gpu-test) sub 1 00:15:00 "N_HPL=60000,TAG=test" HPL/jobs/hpl_gpu.slurm ;;
  gpu)      for nb in 576 1024; do sub 1 00:30:00 "NB=$nb,TAG=nb" HPL/jobs/hpl_gpu.slurm; done
            sub 2 00:30:00 "NB=${BEST_NB:-1024},TAG=final" HPL/jobs/hpl_gpu.slurm ;;
  *) sed -n 2,7p "$0" ;;
esac

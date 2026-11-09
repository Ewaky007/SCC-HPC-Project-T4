#!/bin/bash
# =====================================================================
# HemeLB/jobs/campaign.sh  --  soumet toutes les experiences demandees
# =====================================================================
# A lancer SUR LE LOGIN, depuis la racine du depot, phase par phase :
#
#   bash HemeLB/jobs/campaign.sh test        # 1) Bifurcation, CPU 1 noeud + GPU 1 noeud (~minutes)
#   bash HemeLB/jobs/campaign.sh probe       # 2) Aneurysm-VIRTUAL, 200 pas : estimer le temps/pas
#   bash HemeLB/jobs/campaign.sh cpu         # 3) toutes les experiences CPU
#   bash HemeLB/jobs/campaign.sh gpu         # 4) toutes les experiences GPU
#   bash HemeLB/jobs/campaign.sh profile     # 5) profils MPI 4 puis 2 noeuds, CPU et GPU
#   bash HemeLB/jobs/campaign.sh best        # 6) meilleur run complet (pas officiels) a rendre
#
# Variables utiles :
#   ACCOUNT=r260084         compte Slurm
#   STUDY_STEPS=2000        nb de pas pour les etudes (vide = pas officiels du cas)
#   CPU_TIME / GPU_TIME     limite de temps des jobs (format Slurm)
# Pourquoi un STUDY_STEPS ?  Les etudes (scalabilite, effets) comparent des MLUPS :
# un nombre de pas reduit mais identique pour tous les runs suffit et economise
# les heures partagees. Le run "best" utilise les pas officiels du cas.
# =====================================================================
set -e
cd "$(dirname "$0")/../.."
source common/env_romeo.sh
mkdir -p HemeLB/logs
J=HemeLB/jobs/run_hemelb.slurm
STUDY_STEPS=${STUDY_STEPS:-}
CPU_TIME=${CPU_TIME:-01:00:00}
GPU_TIME=${GPU_TIME:-00:30:00}

# sub <nodes> <time> <VAR=val,...>
sub() {
    local n=$1 t=$2 vars=$3
    local id
    id=$(sbatch --parsable -A "$ACCOUNT" -N "$n" -t "$t" --export=ALL,$vars "$J")
    echo "  job $id : N=$n $vars"
}
S=""; [ -n "$STUDY_STEPS" ] && S=",STEPS=$STUDY_STEPS"

case ${1:-help} in
test)
    echo "== Entrainement sur Bifurcation"
    sub 1 00:15:00 "MODE=cpu,CASE=Bifurcation-TINY,RPN=72,TAG=test"
    sub 1 00:15:00 "MODE=gpu,CASE=Bifurcation-TINY,TAG=test"
    ;;
probe)
    echo "== Aneurysm-VIRTUAL, 200 pas : mesure du temps par pas"
    sub 1 00:30:00 "MODE=cpu,STEPS=200,TAG=probe"
    sub 1 00:20:00 "MODE=gpu,STEPS=200,TAG=probe"
    ;;
cpu)
    echo "== CPU : scalabilite 1/2/4 noeuds (288 rangs/noeud, auto-vectorisation)"
    for n in 1 2 4; do sub $n $CPU_TIME "MODE=cpu,BUILD=cpu-vec,TAG=scaling$S"; done
    echo "== CPU : effet du nombre de rangs MPI sur 1 noeud (288 deja fait ci-dessus)"
    for r in 36 72 144; do sub 1 $CPU_TIME "MODE=cpu,BUILD=cpu-vec,RPN=$r,TAG=ranks$S"; done
    echo "== CPU : effet du monitoring de stabilite (section <monitoring> supprimee)"
    for n in 1 2 4; do sub $n $CPU_TIME "MODE=cpu,BUILD=cpu-vec,XMLOPTS=--no-monitoring,TAG=monitoring$S"; done
    echo "== CPU : effet de la vectorisation (build sans vectorisation)"
    for n in 1 2 4; do sub $n $CPU_TIME "MODE=cpu,BUILD=cpu-novec,TAG=vec$S"; done
    ;;
gpu)
    echo "== GPU : scalabilite 1/2/4 noeuds (4 GPU/noeud, rang 0 coordinateur en plus)"
    for n in 1 2 4; do sub $n $GPU_TIME "MODE=gpu,TAG=scaling$S"; done
    echo "== GPU : frequence d'ecriture x10 plus / x10 moins / aucune"
    for n in 1 2 4; do
        sub $n $GPU_TIME "MODE=gpu,XMLOPTS=--output-factor 0.1,TAG=outfreq_x10more$S"
        sub $n $GPU_TIME "MODE=gpu,XMLOPTS=--output-factor 10,TAG=outfreq_x10less$S"
        sub $n $GPU_TIME "MODE=gpu,XMLOPTS=--no-output,TAG=outfreq_none$S"
    done
    echo "== GPU : levier placement -> 4N rangs (1 GPU inutilise) au lieu de 4N+1"
    for n in 1 4; do sub $n $GPU_TIME "MODE=gpu,EXTRA=0,TAG=extra0$S"; done
    echo "== GPU : 1 et 2 GPU sur 1 noeud (scalabilite intra-noeud)"
    for g in 1 2; do sub 1 $GPU_TIME "MODE=gpu,RPN=$g,TAG=gpus$S"; done
    ;;
profile)
    echo "== Profils MPI (libmpiprof) 4 puis 2 noeuds, CPU et GPU"
    for n in 4 2; do
        sub $n $CPU_TIME "MODE=cpu,PROFILE=1,TAG=profile$S"
        sub $n $GPU_TIME "MODE=gpu,PROFILE=1,TAG=profile$S"
    done
    ;;
best)
    echo "== Meilleure configuration, pas officiels (a adapter apres les etudes)"
    sub ${BEST_NODES:-4} ${BEST_TIME:-00:30:00} "MODE=gpu,TAG=best"
    ;;
*)
    sed -n 2,22p "$0"
    ;;
esac

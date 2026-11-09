#!/bin/bash
# ---------------------------------------------------------------------
# gpu_bind.sh -- lance un rang HemePure-GPU sur les coeurs Grace "voisins" de son GPU
# ---------------------------------------------------------------------
# HemePure-GPU choisit lui-meme son GPU : device = (rang - 1) % nb_GPU,
# et le rang 0 ne calcule pas (il coordonne). Voir SimulationMaster.cu.
# Sur un noeud GH200, le GPU d est colle au CPU Grace d (coeurs 72*d .. 72*d+71) :
# on epingle donc le rang sur ces 72 coeurs pour que ses copies memoire
# restent locales (pas de traversee entre superchips).
# ---------------------------------------------------------------------
r=${OMPI_COMM_WORLD_RANK:-${SLURM_PROCID:-0}}
ngpu=${NGPU_PER_NODE:-4}
if [ "$r" -eq 0 ]; then d=0; else d=$(( (r - 1) % ngpu )); fi
first=$(( 72 * d )); last=$(( 72 * d + 71 ))
# profilage MPI eventuel : la lib n'est chargee que dans l'application, pas dans bash
if [ -n "$MPIPROF_LIB" ]; then export LD_PRELOAD="$MPIPROF_LIB${LD_PRELOAD:+:$LD_PRELOAD}"; fi
exec taskset -c ${first}-${last} "$@"

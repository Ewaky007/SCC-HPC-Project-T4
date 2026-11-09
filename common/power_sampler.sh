#!/bin/bash
# =====================================================================
# common/power_sampler.sh  --  mesure de puissance pendant un run
# =====================================================================
# Lance UNE instance par noeud, en arriere-plan, au debut du job :
#     srun --overlap -N $SLURM_NNODES --ntasks-per-node=1 \
#          bash common/power_sampler.sh $OUTDIR/power 1 &
#     PSAMP=$!
#     ... run ...
#     kill $PSAMP
#
# Ecrit  <dir>/power_<host>.csv  avec une ligne par echantillon :
#     t_epoch,source,id,watts
#   source = gpu      : nvidia-smi power.draw (puissance du GPU Hopper seul)
#   source = module   : nvidia-smi module.power.draw (superchip complet GPU+CPU+memoire), si dispo
#   source = hwmon    : capteurs Grace (/sys/class/hwmon, en microwatts -> W), si lisibles
# common/power_summary.py fait la moyenne sur la fenetre du run.
# =====================================================================
dir=${1:-power}
period=${2:-1}            # periode d'echantillonnage (s)
mkdir -p "$dir"
out="$dir/power_$(hostname -s).csv"
echo "t_epoch,source,id,watts" > "$out"

# Le champ module.power.draw n'existe que sur les drivers recents / GH200 :
# on teste une fois pour ne pas casser la boucle.
has_module=0
nvidia-smi --query-gpu=module.power.draw --format=csv,noheader,nounits >/dev/null 2>&1 && has_module=1

# Capteurs Grace lisibles ?
hw_files=()
for f in /sys/class/hwmon/hwmon*/device/power1_average; do
    [ -r "$f" ] && hw_files+=("$f")
done

while true; do
    t=$(date +%s.%N)
    nvidia-smi --query-gpu=index,power.draw --format=csv,noheader,nounits 2>/dev/null | \
        awk -v t="$t" -F', *' '{print t",gpu,"$1","$2}' >> "$out"
    if [ $has_module = 1 ]; then
        nvidia-smi --query-gpu=index,module.power.draw --format=csv,noheader,nounits 2>/dev/null | \
            awk -v t="$t" -F', *' '{print t",module,"$1","$2}' >> "$out"
    fi
    for f in "${hw_files[@]}"; do
        label=$(cat "$(dirname "$f")/power1_oem_info" 2>/dev/null | tr ' ,' '__')
        uw=$(cat "$f" 2>/dev/null)
        [ -n "$uw" ] && echo "$t,hwmon,${label:-$(basename $(dirname $(dirname $f)))},$(awk -v u=$uw 'BEGIN{print u/1e6}')" >> "$out"
    done
    sleep "$period"
done

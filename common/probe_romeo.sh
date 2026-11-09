#!/bin/bash -l
#SBATCH --job-name=t4_probe
#SBATCH --constraint=armgpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:10:00
#SBATCH --output=probe_%j.out
# =====================================================================
# common/probe_romeo.sh  --  ETAPE 0 : inventaire de ROMEO (10 min max)
# =====================================================================
# Lancement (depuis la racine du depot, sur le login) :
#     sbatch -A r260084 common/probe_romeo.sh
#     (puis renvoie le fichier probe_<jobid>.out)
#
# But : savoir exactement quels modules / paquets spack / outils existent
# sur les noeuds GH200, pour ajuster les scripts de build sans tatonner.
# Rien n'est modifie, on ne fait que lister.
# =====================================================================

sec() { echo; echo "################ $* ################"; }

sec "NOEUD"
hostname; uname -m; lscpu | grep -E "Model name|^CPU\(s\)|Socket|NUMA node[0-9]|MHz"
numactl -H 2>/dev/null | head -20 || echo "numactl absent"
free -g | head -2

sec "GPU"
nvidia-smi
nvidia-smi --query-gpu=name,power.draw,power.limit,clocks.max.sm --format=csv
nvidia-smi -q -d POWER | head -60
sec "CHAMPS PUISSANCE MODULE (GH200)"
nvidia-smi --query-gpu=module.power.draw --format=csv 2>&1 | head -3

sec "HWMON (puissance Grace)"
for h in /sys/class/hwmon/hwmon*; do
  n=$(cat $h/name 2>/dev/null); echo "$h name=$n"
  ls $h/device 2>/dev/null | grep -E "power|oem" | head
  for f in $h/device/power1_oem_info $h/device/power1_average; do
    [ -r $f ] && echo "  $f = $(cat $f)"
  done
done

sec "RESEAU"
ibstat 2>/dev/null | grep -E "CA '|State|Rate" | head -20 || echo "ibstat absent"

sec "MODULES DISPONIBLES"
module avail 2>&1 | head -150

sec "FONCTIONS ROMEO"
type romeo_load_armgpu_env 2>&1 | head -5
romeo_load_armgpu_env 2>&1 | tail -3

sec "SPACK (paquets utiles)"
if command -v spack >/dev/null; then
  for p in openmpi mpich openblas netlib-scalapack scalapack fftw nvpl-blas nvpl-lapack nvpl-scalapack nvpl-fft \
           boost cmake python py-numpy py-matplotlib hdf5 mpip paraview ffmpeg elpa hpl hpcg; do
    echo "--- $p"; spack find -lv $p 2>/dev/null | grep -v "^==>" | head -6
  done
else
  echo "spack absent apres romeo_load_armgpu_env"
fi

sec "PILE NVHPC"
module purge; module load nvhpc/nvhpc-hpcx-cuda12/24.11 2>&1
which mpicc mpicxx mpif90 nvcc nvc++ gcc g++ gfortran
mpicc --version 2>&1 | head -2; mpirun --version 2>&1 | head -2
echo "NVHPC_ROOT=$NVHPC_ROOT"
ls $NVHPC_ROOT/math_libs/lib64 2>/dev/null | head -30
ls -d $NVHPC_ROOT/comm_libs/*/hpcx/*/ompi 2>/dev/null
ompi_info 2>/dev/null | grep -iE "cuda|ucx" | head -5
ls /usr/lib64 | grep -iE "nvpl|openblas|scalapack|fftw" | head

sec "COMPILATEURS SYSTEME"
gcc --version | head -1; gfortran --version 2>&1 | head -1
ls /opt/rh 2>/dev/null

sec "CONTENEURS"
which apptainer singularity enroot podman 2>&1
apptainer --version 2>&1; singularity --version 2>&1
srun --help 2>&1 | grep -i container | head -3
srun --mpi=list 2>&1 | head

sec "PYTHON"
which python3; python3 --version
python3 -c "import numpy, matplotlib; print('numpy', numpy.__version__, 'mpl', matplotlib.__version__)" 2>&1
which pvpython pvbatch ffmpeg 2>&1

sec "INTERNET DEPUIS LE NOEUD DE CALCUL ?"
timeout 8 curl -sI https://github.com | head -1 || echo "pas d'internet depuis le noeud"

sec "ESPACE DISQUE"
df -h $HOME 2>/dev/null; echo "WORK candidats :"; ls -d /gpfs/* 2>/dev/null | head; echo "SCRATCH=$SCRATCH  WORKDIR=$WORKDIR"

sec "SLURM"
sacctmgr -n show assoc user=$USER format=account%20,partition%15,qos%30 2>/dev/null | head
sinfo -s 2>/dev/null | head
echo "FIN"

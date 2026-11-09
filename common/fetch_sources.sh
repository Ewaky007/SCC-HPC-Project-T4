#!/bin/bash
# =====================================================================
# common/fetch_sources.sh  --  telechargements, A LANCER SUR LE LOGIN
# =====================================================================
# Pourquoi sur le login ?  Les noeuds de calcul n'ont peut-etre pas internet
# (le probe le dira). Telecharger ne demande pas d'etre sur ARM ; compiler oui.
#
# Usage :   bash common/fetch_sources.sh [hemelb|openmx|hpl|hpcg|all]
# =====================================================================
set -e
source "$(dirname "$0")/env_romeo.sh"
what=${1:-all}
cd "$SRC"

fetch_hemelb() {
    echo "== HemeLB (variante HemePure, la seule utilisee par l'epreuve)"
    # NB : PAS le depot hemelb-emulator/hemelb (HemeLB "complet", deps differentes :
    # c'est lui qui reclamait TinyXML). HemePure embarque ses deps dans dep/.
    [ -d HemePure ]     || git clone https://github.com/UCL-CCS/HemePure.git
    [ -d HemePure-GPU ] || git clone -b HIP-CUDA-ROCM_SL https://github.com/UCL-CCS/HemePure-GPU.git
    [ -d hemeXtract ]   || git clone https://github.com/UCL-CCS/hemeXtract.git
    # Boost : le CMake des deps cherche boost_1_83_0.tar.gz dans dep/src, sinon
    # il le telecharge (echoue si le noeud n'a pas internet) -> on le pre-telecharge.
    [ -f boost_1_83_0.tar.gz ] || wget -q https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.gz
    for r in HemePure HemePure-GPU; do cp -n boost_1_83_0.tar.gz $r/dep/src/ ; done
    ( cd HemePure && git rev-parse HEAD > ../HemePure.commit )
    ( cd HemePure-GPU && git rev-parse HEAD > ../HemePure-GPU.commit )
    echo "   Commits notes dans $SRC/*.commit (a reporter dans le journal)"
    echo "   ENTREES : telecharger a la main depuis la page officielle HemeLB ISC26"
    echo "   (pieces jointes hemelb_tiny / Bifurcation-TINY / Aneurysm-VIRTUAL) et les"
    echo "   deposer dans $INPUTS/hemelb/  (scp depuis ton PC si besoin)."
    mkdir -p $INPUTS/hemelb
}

fetch_openmx() {
    echo "== OpenMX 3.9 (base DFT_DATA19) + sources 3.962"
    [ -f openmx3.9.tar.gz ] || wget -q https://www.openmx-square.org/openmx3.9.tar.gz
    [ -d openmx3.9 ] || tar xf openmx3.9.tar.gz
    echo "   source3.962.tar.gz : piece jointe de la page OpenMX ISC25 (ou fournie par l'enseignant)."
    echo "   -> la copier dans $SRC/ puis relancer ce script."
    if [ -f source3.962.tar.gz ] && [ ! -d openmx3.9/source3.962 ]; then
        rm -rf openmx3.9/source
        tar xf source3.962.tar.gz -C openmx3.9
        ls openmx3.9
    fi
    mkdir -p $INPUTS/openmx
}

fetch_hpl() {
    echo "== HPL 2.3 netlib"
    [ -f hpl-2.3.tar.gz ] || wget -q https://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz
    [ -d hpl-2.3 ] || tar xf hpl-2.3.tar.gz
}

fetch_hpcg() {
    echo "== HPCG reference"
    [ -d hpcg ] || git clone https://github.com/hpcg-benchmark/hpcg.git
}

fetch_container() {
    echo "== Conteneur NVIDIA HPC-Benchmarks (ARM64 !)"
    # Le login est x86 : sans --arch arm64, apptainer tirerait l'image x86 -> inutilisable.
    if command -v apptainer >/dev/null; then
        [ -f $SIF/hpc-benchmarks_25.04.sif ] || \
          apptainer pull --arch arm64 $SIF/hpc-benchmarks_25.04.sif docker://nvcr.io/nvidia/hpc-benchmarks:25.04
    else
        echo "   apptainer absent sur le login : le pull se fera dans le job (voir HPL/README.md)"
    fi
}

case $what in
  hemelb) fetch_hemelb ;;
  openmx) fetch_openmx ;;
  hpl)    fetch_hpl; fetch_container ;;
  hpcg)   fetch_hpcg; fetch_container ;;
  all)    fetch_hemelb; fetch_openmx; fetch_hpl; fetch_hpcg; fetch_container ;;
esac
echo "OK -> $SRC"

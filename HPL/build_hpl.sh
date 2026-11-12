#!/bin/bash


cd /project/r260084/francoisf/SCC-HPC-Project-T4/HPL/hpl-2.3

spack load gcc
spack load openmpi
spack load openblas

make arch=ARM_Grace clean_arch_all

make arch=ARM_Grace
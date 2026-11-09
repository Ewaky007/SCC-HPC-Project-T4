# Poster content (A0 portrait, English) — Team T4

> Text to lay out on the poster. Items in _italics_ are placeholders to fill after the runs.
> Each block = one challenge, with its owner's name.

---

## Header band

**Team T4 — URCA ISC27 SCC selection project**
Kévin William · François Fabre · Mathéo Brugnon

**Machine:** ROMEO (URCA), NVIDIA GH200 nodes — 4 × (Grace 72-core Neoverse-V2 + H100 96 GB) per node, aarch64, 4 × 200 Gb/s InfiniBand.

**Our challenges:** HemeLB (GPU app) · OpenMX (CPU app) · HPL (benchmark) · HPCG (benchmark)

**Main choices:**
- Everything ported from x86/Intel to ARM: GCC `-mcpu=neoverse-v2`, OpenBLAS/ScaLAPACK/FFTW instead of MKL, no SSE/AVX intrinsics.
- One rank per GPU pinned to its neighbouring Grace CPU and memory.
- In-house PMPI profiler (LD_PRELOAD, no recompilation) used for every MPI profile.
- Every result is reproducible from versioned scripts (`build/`, `jobs/campaign.sh`).

---

## Block 1 — HemeLB (HemePure) · Kévin William

**Best configuration:** _N nodes, 4N+1 MPI ranks (4 GPUs per node + 1 coordinating rank), output disabled/…_ → **_X_ MLUPS** (_Y_ MLUPS per GPU). CPU best: _Z_ MLUPS (_w_ MLUPS per core) on _n_ nodes.

**Scaling:** figure `HemeLB/results/scaling_cpu_gpu.png` — strong scaling of Aneurysm-VIRTUAL on 1, 2, 4 nodes, Grace CPUs vs Hopper GPUs.

**Top 3 MPI calls (4 nodes):** _e.g. MPI_Isend / MPI_Irecv / MPI_Waitall_ → _halo exchange between neighbouring sub-domains dominates; rank 0 only coordinates (gathers, reductions) and spends most of its time waiting._

**Effects measured:** MPI ranks per node, stability monitoring, auto-vectorisation (`-O3` vs `-fno-tree-vectorize`), output frequency (×10 more, ×10 less, none) — figure `effects.png`.

**Visualisation:** velocity magnitude in the aneurysm (max-intensity projection) — `HemeLB/results/visu/`.

**Main difficulty:** the code targets x86 (SSE/AVX intrinsics) and single-GPU nodes; we disabled the intrinsics, tuned `-mcpu` for Grace, and launched 4N+1 ranks because rank 0 does not compute and would otherwise leave one GPU idle.

---

## Block 2 — OpenMX · Kévin William

**Best configuration:** NVC on 4 Grace nodes, _r_ MPI ranks × _t_ OpenMP threads → **_T_ s** total computational time.

**Scaling:** `OpenMX/results/scaling.png` (1, 2, 4 nodes) and `omp_sweep.png` (MPI/OpenMP ratio).

**Top 3 MPI calls (4 nodes):** _…_ → _…_

**Visualisation:** NVC structure in OpenMX Viewer (video).

**Main difficulty:** the Intel/MKL makefile; rebuilt with GCC + OpenBLAS/ScaLAPACK/FFTW, `-fcommon` and `-fallow-argument-mismatch` for modern GCC, SSE replaced by OpenMX's `mimic_sse.h`.

---

## Block 3 — HPL · François Fabre

| Run | N | NB | P×Q | Rmax | Rmax/Rpeak | Power | GFLOPS/W |
|---|---|---|---|---|---|---|---|
| netlib HPL 2.3, Grace, 1 node | _…_ | _…_ | _…_ | _…_ | _…_ | _…_ | _…_ |
| NVIDIA HPL, 1 node (4 GPUs) | _…_ | _…_ | 2×2 | _…_ | _…_ | _…_ | _…_ |
| NVIDIA HPL, 2 nodes (8 GPUs) | _…_ | _…_ | 2×4 | _…_ | _…_ | _…_ | _…_ |

**Main difficulty:** _…_

---

## Block 4 — HPCG · Mathéo Brugnon

| Run (≥ 30 min) | GFLOP/s | Power | GFLOPS/W | HPCG / HPL |
|---|---|---|---|---|
| Reference, Grace, 1 node | _…_ | _…_ | _…_ | _…_ |
| NVIDIA, 1 node (4 GPUs) | _…_ | _…_ | _…_ | _…_ |

**Why HPCG ≪ HPL:** sparse matrix-vector products and Gauss-Seidel read ~8 bytes for ~2 flops → memory-bandwidth bound, while HPL's dense DGEMM reuses data and runs near peak compute.

**Main difficulty:** the default ROMEO environment was x86; switching to the ARM environment and the CUDA-aware OpenMPI from spack.

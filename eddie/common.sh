#!/bin/bash
# Shared environment for all Eddie jobs: finds Julia and puts the package
# depot on scratch (home quota is small, and scratch is faster).

SCRATCH_ROOT="/exports/eddie/scratch/${USER}"
[[ -d "${SCRATCH_ROOT}" ]] || SCRATCH_ROOT="${HOME}"

export JULIA_DEPOT_PATH="${SCRATCH_ROOT}/julia_depot"
export JULIAUP_DEPOT_PATH="${SCRATCH_ROOT}/juliaup_depot"
export JULIA_PKG_PRECOMPILE_AUTO=0          # precompile once in setup, never concurrently
export GKSwstype=100                        # Plots.jl/GR without a display
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
JULIAUP_DIR="${SCRATCH_ROOT}/juliaup"

source /etc/profile.d/modules.sh
module purge

find_julia() {
  # 1. an Eddie module, if one exists
  local mod
  for mod in julia/1.11 julia/1.10 julia igmm/apps/julia; do
    if module load "${mod}" 2>/dev/null && command -v julia >/dev/null 2>&1; then
      echo "Loaded module: ${mod}"
      return 0
    fi
  done
  # 2. a juliaup install on scratch (created by setup.qsub.sh)
  if [[ -x "${JULIAUP_DIR}/bin/julia" ]]; then
    export PATH="${JULIAUP_DIR}/bin:${PATH}"
    echo "Using juliaup Julia in ${JULIAUP_DIR}"
    return 0
  fi
  return 1
}

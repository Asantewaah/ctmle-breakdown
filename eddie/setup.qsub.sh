#!/bin/bash
# =============================================================================
# eddie/setup.qsub.sh — one-time Julia install + package precompile
#
# Installs Julia (via juliaup, on scratch) if no Julia module is available,
# then instantiates and precompiles the project ONCE, so the array tasks never
# precompile concurrently into the same depot.
# =============================================================================
#$ -N ctmle-setup
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -pe sharedmem 4
#$ -l h_rt=03:00:00
#$ -l h_vmem=4G
#$ -m bea
#$ -M s2719123@ed.ac.uk
#$ -o logs/$JOB_NAME-$JOB_ID.out
#$ -e logs/$JOB_NAME-$JOB_ID.err

set -euo pipefail
cd "${SGE_O_WORKDIR:-$PWD}"
mkdir -p logs
source eddie/common.sh

echo "========== Julia setup =========="
echo "Job ID : ${JOB_ID:-local}   Host : ${HOSTNAME}   Started : $(date)"

if ! find_julia; then
  echo "No Julia found; installing juliaup into ${JULIAUP_DIR}"
  curl -fsSL https://install.julialang.org | sh -s -- --yes --path "${JULIAUP_DIR}" --default-channel 1.11
  export PATH="${JULIAUP_DIR}/bin:${PATH}"
fi
julia --version

echo "Instantiating and precompiling project (single process)..."
JULIA_PKG_PRECOMPILE_AUTO=1 julia --project=. -t "${NSLOTS:-4}" -e '
  using Pkg
  Pkg.instantiate()
  Pkg.precompile()
  include("src/simulation.jl")
  sim = simulate_data(StableRNG(1); n = 300, instrument = 1.0)   # warm-up + smoke check
  display(estimate_all(sim.data))
'
echo "========== Setup complete: $(date) =========="

#!/bin/bash
# =============================================================================
# eddie/postprocess.qsub.sh — combine batches and summarise
# Held automatically on the array job by eddie/submit.sh.
# =============================================================================
#$ -N ctmle-post
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -pe sharedmem 1
#$ -l h_rt=02:00:00
#$ -l h_vmem=16G
#$ -m ea
#$ -o logs/$JOB_NAME-$JOB_ID.out
#$ -e logs/$JOB_NAME-$JOB_ID.err

set -euo pipefail
cd "${SGE_O_WORKDIR:-$PWD}"
mkdir -p logs
source eddie/common.sh
find_julia || { echo "ERROR: Julia not found." >&2; exit 1; }

n_batches=$(ls results/batches/*.csv 2>/dev/null | wc -l)
echo "Found ${n_batches} of 20 batch files"
[[ "${n_batches}" -eq 20 ]] || echo "WARNING: some tasks did not finish; summarising what is there."

julia --project=. scripts/combine_results.jl
echo "Done $(date). See results/summary.md."
echo "Make the figures on your own machine: python scripts/make_figures.py"

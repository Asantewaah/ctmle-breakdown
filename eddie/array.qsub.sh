#!/bin/bash
# =============================================================================
# eddie/array.qsub.sh — simulation array job
#
# 20 tasks = 5 instrument strengths x 4 chunks of 25 replicates (100 per level).
# Each task writes its own file to results/batches/ (skipped if it already
# exists, so the whole array is safe to resubmit after failures).
#
# Smoke test one task first and check its run time in the log:
#   qsub -t 1-1 eddie/array.qsub.sh
# =============================================================================
#$ -N ctmle-sim
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -t 1-20
#$ -pe sharedmem 8
#$ -l h_rt=02:00:00
#$ -l h_vmem=8G
#$ -m a
#$ -M s2719123@ed.ac.uk
#$ -o logs/$JOB_NAME-$JOB_ID.$TASK_ID.out
#$ -e logs/$JOB_NAME-$JOB_ID.$TASK_ID.err

set -euo pipefail
cd "${SGE_O_WORKDIR:-$PWD}"
mkdir -p logs results/batches
source eddie/common.sh
find_julia || { echo "ERROR: Julia not found. Run eddie/setup.qsub.sh first." >&2; exit 1; }

LEVELS=(0.0 0.5 1.0 1.5 2.0)
N_CHUNKS=4
REPS_PER_CHUNK=25

TASK=${SGE_TASK_ID:-1}
LEVEL_IDX=$(( (TASK - 1) / N_CHUNKS ))
CHUNK=$(( (TASK - 1) % N_CHUNKS ))
export INSTRUMENT_LEVELS="${LEVELS[$LEVEL_IDX]}"
export REP_START=$(( CHUNK * REPS_PER_CHUNK + 1 ))
export REP_END=$(( REP_START + REPS_PER_CHUNK - 1 ))
export BATCH_FILE="results/batches/level${INSTRUMENT_LEVELS}_reps$(printf '%03d' ${REP_START})-$(printf '%03d' ${REP_END}).csv"

echo "========== C-TMLE simulation task =========="
echo "Job ${JOB_ID:-local} task ${TASK} on ${HOSTNAME}, ${NSLOTS:-1} slots"
echo "Instrument strength ${INSTRUMENT_LEVELS}, replicates ${REP_START}-${REP_END}"
echo "Output ${BATCH_FILE}"
echo "Started $(date)"

julia --project=. -t "${NSLOTS:-1}" --heap-size-hint=40G scripts/run_simulation.jl

echo "Finished $(date)"

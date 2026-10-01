#!/bin/bash
# =============================================================================
# eddie/submit.sh — submit setup -> 20-task array -> postprocess, chained.
#
# Run from the repository root on an Eddie login node:
#   eddie/submit.sh              # full run
#   eddie/submit.sh smoke        # setup + array task 1 only (check timing first)
#
# Setup only needs to succeed once. To skip it on later submissions:
#   SKIP_SETUP=1 eddie/submit.sh smoke
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p logs results/batches

if [[ "${SKIP_SETUP:-0}" == "1" ]]; then
  setup_id="none"
  hold=()
  echo "Setup job:       skipped (SKIP_SETUP=1)"
else
  setup_id=$(qsub -terse eddie/setup.qsub.sh)
  hold=(-hold_jid "${setup_id}")
  echo "Setup job:       ${setup_id}"
fi

if [[ "${1:-}" == "smoke" ]]; then
  array_id=$(qsub -terse -t 1-1 ${hold[@]+"${hold[@]}"} eddie/array.qsub.sh | cut -d. -f1)
  echo "Smoke test task: ${array_id} (task 1 only)"
  echo "Watch progress with: tail -f logs/ctmle-sim-${array_id}.1.out"
  echo "Each finished replicate prints its run time, so after a few you can estimate the total."
  exit 0
fi

array_id=$(qsub -terse ${hold[@]+"${hold[@]}"} eddie/array.qsub.sh | cut -d. -f1)
echo "Array job:       ${array_id} (20 tasks)"

post_id=$(qsub -terse -hold_jid "${array_id}" eddie/postprocess.qsub.sh)
echo "Postprocess job: ${post_id} (runs when all array tasks have finished)"
echo "Monitor with:    qstat -u ${USER}"
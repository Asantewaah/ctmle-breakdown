# Repeat the analysis on many simulated datasets for each instrument strength.
#
# On one machine (all settings, then the summary):
#   julia --project -t auto scripts/run_simulation.jl
#
# As one task of the Eddie array job (eddie/array.qsub.sh sets these):
#   INSTRUMENT_LEVELS=0.5 REP_START=1 REP_END=25 BATCH_FILE=results/batches/x.csv \
#     julia --project -t 8 scripts/run_simulation.jl
# In batch mode only the raw rows are written; scripts/combine_results.jl
# joins the batches and writes the summary.
#
# Other settings: N_REPS (single-machine mode, default 100), N_OBS (default 1000).

include(joinpath(@__DIR__, "..", "src", "simulation.jl"))
include(joinpath(@__DIR__, "..", "src", "reporting.jl"))

const N_OBS      = parse(Int, get(ENV, "N_OBS", "1000"))
const BATCH_FILE = get(ENV, "BATCH_FILE", "")
const LEVELS     = haskey(ENV, "INSTRUMENT_LEVELS") ?
                   parse.(Float64, split(ENV["INSTRUMENT_LEVELS"], ",")) : [0.0, 0.5, 1.0, 1.5, 2.0]
const REPS       = haskey(ENV, "REP_START") ?
                   (parse(Int, ENV["REP_START"]):parse(Int, ENV["REP_END"])) :
                   (1:parse(Int, get(ENV, "N_REPS", "100")))
const OUT        = joinpath(@__DIR__, "..", "results")

# Output to a log file is buffered, so flush after every message: if the
# scheduler kills the job, the log still shows how far it got.
say(msg) = (println(msg); flush(stdout))

if !isempty(BATCH_FILE) && isfile(BATCH_FILE)
    say("$(BATCH_FILE) already exists; nothing to do.")
    exit(0)
end

jobs = [(level, rep) for level in LEVELS for rep in REPS]
outputs = Vector{DataFrame}(undef, length(jobs))
n_done = Threads.Atomic{Int}(0)
start = time()

say(@sprintf("Running %d analyses (n = %d) on %d thread(s): strengths %s, replicates %d-%d",
             length(jobs), N_OBS, Threads.nthreads(), join(LEVELS, ", "), first(REPS), last(REPS)))

Threads.@threads for i in eachindex(jobs)
    level, rep = jobs[i]
    t0 = time()
    rng = StableRNG(10_000 * rep + round(Int, 100 * level))
    sim = simulate_data(rng; n = N_OBS, instrument = level)
    res = estimate_all(sim.data)
    res[!, :instrument] .= level
    res[!, :rep] .= rep
    outputs[i] = res
    GC.gc()
    GC.gc()
    k = Threads.atomic_add!(n_done, 1) + 1
    slowest = res.estimator[argmax(res.seconds)]
    say(@sprintf("  %3d / %d  strength %.1f rep %3d  %5.0f s (slowest: %s %.0f s)  elapsed %.0f min",
                 k, length(jobs), level, rep, time() - t0, slowest, maximum(res.seconds), (time() - start) / 60))
end

results = vcat(outputs...)

if isempty(BATCH_FILE)
    write_outputs(results, OUT)
else
    mkpath(dirname(BATCH_FILE))
    tmp = BATCH_FILE * ".tmp"
    CSV.write(tmp, results)
    mv(tmp, BATCH_FILE; force = true)     # appears only when complete
    say(@sprintf("Wrote %d rows to %s in %.1f min.", nrow(results), BATCH_FILE, (time() - start) / 60))
end
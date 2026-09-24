# Repeat the analysis on many simulated datasets for each instrument strength.
#
#   julia --project -t auto scripts/run_simulation.jl
#
# Settings can be changed with environment variables, e.g. N_REPS=20 for a quick run.

include(joinpath(@__DIR__, "..", "src", "simulation.jl"))
using CSV
using Printf

const INSTRUMENT_LEVELS = [0.0, 0.5, 1.0, 1.5, 2.0]
const N_REPS = parse(Int, get(ENV, "N_REPS", "100"))
const N_OBS  = parse(Int, get(ENV, "N_OBS", "1000"))
const OUT    = joinpath(@__DIR__, "..", "results")

jobs = [(level, rep) for level in INSTRUMENT_LEVELS for rep in 1:N_REPS]
outputs = Vector{DataFrame}(undef, length(jobs))
n_done = Threads.Atomic{Int}(0)
start = time()

println("Running $(length(jobs)) analyses on $(Threads.nthreads()) thread(s)...")
Threads.@threads for i in eachindex(jobs)
    level, rep = jobs[i]
    rng = StableRNG(10_000 * rep + round(Int, 100 * level))
    sim = simulate_data(rng; n = N_OBS, instrument = level)
    res = estimate_all(sim.data)
    res[!, :instrument] .= level
    res[!, :rep] .= rep
    outputs[i] = res
    k = Threads.atomic_add!(n_done, 1) + 1
    if k % 25 == 0 || k == length(jobs)
        @printf("  %d / %d done (%.0f s)\n", k, length(jobs), time() - start)
    end
end

results = vcat(outputs...)
mkpath(OUT)
CSV.write(joinpath(OUT, "simulation_results.csv"), results)

summ = summarise(results)
CSV.write(joinpath(OUT, "summary.csv"), summ)

# A Markdown table for the README
open(joinpath(OUT, "summary.md"), "w") do io
    println(io, "| Instrument strength | Estimator | Bias | SD | RMSE | 95% CI coverage | Median CI width |")
    println(io, "|---|---|---|---|---|---|---|")
    for r in eachrow(summ)
        @printf(io, "| %.1f | %s | %.3f | %.3f | %.3f | %.0f%% | %.3f |\n",
                r.instrument, r.estimator, r.bias, r.sd, r.rmse, 100r.coverage, r.median_ci_width)
    end
end

failed = count(!isfinite, results.estimate)
println("\nSaved results to results/. Failed fits: $failed of $(nrow(results)).")
show(stdout, MIME("text/plain"), summ; allrows = true, allcols = true)
println()

# Writing simulation results and their summary to results/.
# Used by scripts/run_simulation.jl (single-machine runs) and
# scripts/combine_results.jl (after an Eddie array job).

using CSV
using Printf

"""
    write_outputs(results, outdir)

Save the raw results, the per-setting summary (CSV) and a Markdown summary table
for the README, then print the summary.
"""
function write_outputs(results::DataFrame, outdir::AbstractString)
    mkpath(outdir)
    sort!(results, [:instrument, :rep])
    CSV.write(joinpath(outdir, "simulation_results.csv"), results)

    summ = summarise(results)
    CSV.write(joinpath(outdir, "summary.csv"), summ)

    open(joinpath(outdir, "summary.md"), "w") do io
        println(io, "| Instrument strength | Estimator | Bias | SD | RMSE | 95% CI coverage | Median CI width |")
        println(io, "|---|---|---|---|---|---|---|")
        for r in eachrow(summ)
            @printf(io, "| %.1f | %s | %.3f | %.3f | %.3f | %.0f%% | %.3f |\n",
                    r.instrument, r.estimator, r.bias, r.sd, r.rmse, 100r.coverage, r.median_ci_width)
        end
    end

    failed = count(!isfinite, results.estimate)
    println("\nSaved results to $(outdir). Failed fits: $failed of $(nrow(results)).")
    show(stdout, MIME("text/plain"), summ; allrows = true, allcols = true)
    println()
    flush(stdout)
    return summ
end

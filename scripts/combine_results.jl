# Join the batch files written by the Eddie array job and summarise them.
#
#   julia --project scripts/combine_results.jl

include(joinpath(@__DIR__, "..", "src", "simulation.jl"))
include(joinpath(@__DIR__, "..", "src", "reporting.jl"))

const OUT = joinpath(@__DIR__, "..", "results")
files = filter(f -> endswith(f, ".csv"), readdir(joinpath(OUT, "batches"); join = true))
isempty(files) && error("No batch files in results/batches/. Has the array job run?")

println("Combining $(length(files)) batch files")
results = vcat([CSV.read(f, DataFrame) for f in files]...)
write_outputs(results, OUT)

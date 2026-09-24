# Figures and the animated GIF for the README, from results/simulation_results.csv.
#
#   julia --project scripts/make_figures.jl

include(joinpath(@__DIR__, "..", "src", "simulation.jl"))
using CSV
using Plots
using Printf

const RES = joinpath(@__DIR__, "..", "results")
const FIG = joinpath(@__DIR__, "..", "figures")
mkpath(FIG)

results = CSV.read(joinpath(RES, "simulation_results.csv"), DataFrame)
summ = CSV.read(joinpath(RES, "summary.csv"), DataFrame)

INK, GOLD, BLUE, GREY = colorant"#1D1B4C", colorant"#F2A900", colorant"#2F45C9", colorant"#9A99B8"
COLOURS = Dict(
    "Naive difference in means"     => GREY,
    "One-step (AIPW)"               => colorant"#C0392B",
    "TMLE (unweighted)"             => colorant"#E67E22",
    "TMLE (weighted)"               => BLUE,
    "C-TMLE (greedy)"               => INK,
    "C-TMLE (adaptive correlation)" => colorant"#7B4FB0",
    "Oracle TMLE"                   => GOLD,
)
default(fontfamily = "sans-serif", framestyle = :box, grid = false, titlefontsize = 12,
        guidefontsize = 10, tickfontsize = 9, legendfontsize = 8, dpi = 150)

short = Dict(
    "Naive difference in means" => "Naive", "One-step (AIPW)" => "AIPW",
    "TMLE (unweighted)" => "TMLE\n(unweighted)", "TMLE (weighted)" => "TMLE\n(weighted)",
    "C-TMLE (greedy)" => "C-TMLE\n(greedy)", "C-TMLE (adaptive correlation)" => "C-TMLE\n(adaptive)",
    "Oracle TMLE" => "Oracle",
)

# 1. Coverage and interval width as instruments get stronger
p1 = plot(title = "95% CI coverage", xlabel = "Instrument strength", ylabel = "Coverage",
          ylims = (0, 1.02), legend = :bottomleft)
hline!(p1, [0.95]; color = GREY, ls = :dash, label = "")
p2 = plot(title = "Median CI width", xlabel = "Instrument strength", ylabel = "Width",
          yscale = :log10, legend = false)
for name in ESTIMATOR_ORDER
    s = sort(filter(r -> r.estimator == name, summ), :instrument)
    plot!(p1, s.instrument, s.coverage; lw = 2.5, marker = :circle, ms = 4, color = COLOURS[name], label = name)
    plot!(p2, s.instrument, s.median_ci_width; lw = 2.5, marker = :circle, ms = 4, color = COLOURS[name], label = name)
end
savefig(plot(p1, p2; layout = (1, 2), size = (1100, 420), left_margin = 5Plots.mm, bottom_margin = 6Plots.mm),
        joinpath(FIG, "coverage_and_width.png"))

# 2. Strip plot of estimates at one instrument strength
const YLIM = (-1.0, 5.0)

function strip_plot(level; title_prefix = "")
    d = filter(r -> r.instrument == level && isfinite(r.estimate), results)
    p = plot(; ylims = YLIM, legend = false, size = (1000, 480), ylabel = "Estimated ATE",
             title = @sprintf("%sInstrument strength %.1f", title_prefix, level),
             xticks = (1:length(ESTIMATOR_ORDER), [short[n] for n in ESTIMATOR_ORDER]),
             bottom_margin = 8Plots.mm, left_margin = 5Plots.mm)
    hline!(p, [TRUE_ATE]; color = GOLD, lw = 3)
    annotate!(p, length(ESTIMATOR_ORDER) + 0.45, TRUE_ATE + 0.18, text("True effect", 8, GOLD, :right))
    for (i, name) in enumerate(ESTIMATOR_ORDER)
        e = d.estimate[d.estimator .== name]
        isempty(e) && continue
        clipped = clamp.(e, YLIM[1] + 0.05, YLIM[2] - 0.05)       # off-scale values drawn at the edge
        x = i .+ 0.28 .* (rand(StableRNG(i), length(e)) .- 0.5)
        scatter!(p, x, clipped; ms = 3.2, markerstrokewidth = 0, alpha = 0.55, color = COLOURS[name])
        n_off = count(v -> v < YLIM[1] || v > YLIM[2], e)
        n_off > 0 && annotate!(p, i, YLIM[2] - 0.25, text("$n_off off scale", 7, INK))
    end
    return p
end

savefig(strip_plot(2.0), joinpath(FIG, "estimates_strong_instruments.png"))

# 3. Animated GIF stepping through instrument strengths
levels = sort(unique(results.instrument))
anim = @animate for level in vcat(levels, fill(levels[end], 2), reverse(levels)[2:end-1])
    strip_plot(level; title_prefix = "More adjustment is not always better  |  ")
end
gif(anim, joinpath(FIG, "instrument_sweep.gif"); fps = 1)

println("Saved figures to figures/")

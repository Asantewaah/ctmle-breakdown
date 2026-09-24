### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 17b3f15c-ef67-48f2-aafe-c86e3c430ff4
md"""
# More adjustment is not always better
### An interactive tour of TMLE and C-TMLE with [TMLE.jl](https://github.com/TARGENE/TMLE.jl)

*Juliet Asantewaa Sarpong · University of Edinburgh*

When we estimate a causal effect from observational data, the usual instinct is to **adjust for every covariate we have**. That removes confounding, but some covariates do harm: variables that only affect who gets treated (**instruments**) push propensity scores towards 0 and 1, and estimators that weight by the propensity score become unstable.

**Collaborative TMLE (C-TMLE)** chooses which covariates to put in the propensity score model *based on how much they help estimate the effect*, rather than how well they predict treatment. This notebook lets you watch that happen. Move the sliders and every estimator reruns on a freshly simulated dataset.
"""

# ╔═╡ 40d7e96b-eda0-4e4d-83fa-f2675ce02ac0
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using PlutoUI, Plots, Printf
    include(joinpath(@__DIR__, "..", "src", "simulation.jl"))
end

# ╔═╡ b7c1dfb2-7ff4-4d61-afa7-9fb1c525c614
md"""
## The set-up

Every dataset has one binary treatment `A`, one continuous outcome `Y` and **14 candidate covariates**. The true average treatment effect is always **$(TRUE_ATE)**. The analyst sees all 14 covariates but not their roles:

| Covariates | Role | Affects treatment? | Affects outcome? |
|---|---|---|---|
| `W1`–`W3` | Confounders | Yes | Yes |
| `Z1`–`Z3` | Instruments | **Yes** | No |
| `X1`–`X3` | Outcome predictors | No | Yes |
| `N1`–`N5` | Noise | No | No |

The *Oracle TMLE* is given the true roles, as a benchmark for what C-TMLE is trying to achieve without being told.
"""

# ╔═╡ 7df69425-823e-4d8c-bb18-3900aafb1278
md"""
## Try it

**Instrument strength** $(@bind instrument Slider(0:0.25:2.5; default = 1.5, show_value = true))

**Confounding strength** $(@bind confounding Slider(0:0.25:2; default = 1.0, show_value = true))

**Sample size** $(@bind n_obs Select([500, 1000, 2000]; default = 1000))

**Random seed** $(@bind seed Slider(1:100; default = 1, show_value = true))
"""

# ╔═╡ cb77cc6e-f906-4d7c-a029-14fedf98e1dc
sim = simulate_data(StableRNG(seed); n = n_obs, confounding = confounding, instrument = instrument);

# ╔═╡ df09b26d-e206-44d2-8378-7dfef389341e
results = estimate_all(sim.data)

# ╔═╡ 29c0d8a7-e00b-4760-b320-2abf6d69b836
let
    d = results[isfinite.(results.estimate), :]
    order = [n for n in reverse(ESTIMATOR_ORDER) if n in d.estimator]
    d = d[[findfirst(==(n), d.estimator) for n in order], :]
    y = 1:nrow(d)
    colours = [n == "Oracle TMLE" ? "#F2A900" : n == "Naive difference in means" ? "#9A99B8" :
               startswith(n, "C-TMLE") ? "#1D1B4C" : "#2F45C9" for n in d.estimator]
    lo = clamp.(d.estimate .- d.lower, 0, 10); hi = clamp.(d.upper .- d.estimate, 0, 10)
    p = scatter(d.estimate, y; xerror = (lo, hi), color = colours, markerstrokecolor = colours,
                ms = 7, yticks = (y, d.estimator), legend = false, xlims = (-1, 5),
                xlabel = "Estimated average treatment effect (95% CI)", size = (820, 380),
                framestyle = :box, grid = false, left_margin = 4Plots.mm,
                title = @sprintf("Instrument strength %.2f, n = %d", instrument, n_obs))
    vline!(p, [TRUE_ATE]; color = "#F2A900", lw = 3)
    p
end

# ╔═╡ 7ad4c8dc-fdf2-4a8f-afdd-ca20c0ca659c
let
    ps = sim.propensity
    histogram(ps; bins = 0:0.025:1, color = "#1D1B4C", linecolor = :white, legend = false,
              xlabel = "True probability of treatment", ylabel = "Individuals", size = (820, 260),
              framestyle = :box, grid = false,
              title = @sprintf("%.0f%% of individuals have a treatment probability below 0.05 or above 0.95",
                               100 * mean((ps .< 0.05) .| (ps .> 0.95))))
end

# ╔═╡ 07ea57b3-d029-45f4-84c9-0353f09d4e8b
md"""
## What to look for

- **Set instrument strength to 0.** There are no harmful covariates, so all the adjusted estimators agree and cover the truth. Only the naive comparison is off, because of confounding.
- **Now push instrument strength above 1.5.** The propensity scores pile up near 0 and 1 (histogram above). Estimators that rely on the full propensity score, such as the one-step estimator and unweighted TMLE, can start to swing wildly or produce very wide intervals, even though they adjust for all the right confounders.
- **Compare weighted and unweighted TMLE.** The weighted fluctuation (TMLE.jl's default) is designed to be more robust to extreme propensity scores. How much more robust is it here?
- **Watch C-TMLE against the oracle.** By adding covariates to the propensity score only when they improve the targeted fit, C-TMLE should tend to leave the instruments out and behave like an analyst who knew the true roles.
- **Change the seed** to see how much each estimator varies from one dataset to the next. The simulation study in `scripts/run_simulation.jl` repeats this hundreds of times to measure bias and coverage properly.
"""

# ╔═╡ aad3ebd4-40f3-44c2-8aa5-5ba2b32a78d1
md"""
## How the estimators are called

All of this uses TMLE.jl's standard interface. For example, the greedy C-TMLE is:

```julia
Ψ = ATE(
    outcome = :Y,
    treatment_values = (A = (case = true, control = false),),
    treatment_confounders = (A = ALL_COVARIATES,)
)
ctmle = Tmle(collaborative_strategy = GreedyStrategy(patience = 5))
result, cache = ctmle(Ψ, data)
```

See `src/simulation.jl` for the full set.
"""

# ╔═╡ Cell order:
# ╠═17b3f15c-ef67-48f2-aafe-c86e3c430ff4
# ╠═40d7e96b-eda0-4e4d-83fa-f2675ce02ac0
# ╠═b7c1dfb2-7ff4-4d61-afa7-9fb1c525c614
# ╠═7df69425-823e-4d8c-bb18-3900aafb1278
# ╠═cb77cc6e-f906-4d7c-a029-14fedf98e1dc
# ╠═df09b26d-e206-44d2-8378-7dfef389341e
# ╠═29c0d8a7-e00b-4760-b320-2abf6d69b836
# ╠═7ad4c8dc-fdf2-4a8f-afdd-ca20c0ca659c
# ╠═07ea57b3-d029-45f4-84c9-0353f09d4e8b
# ╠═aad3ebd4-40f3-44c2-8aa5-5ba2b32a78d1

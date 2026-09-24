# Data-generating process and estimators for the C-TMLE explainer.
#
# The analyst sees 14 candidate covariates but does not know their roles:
#   W1-W3  true confounders   (affect treatment AND outcome)
#   Z1-Z3  instruments        (affect treatment only)
#   X1-X3  outcome predictors (affect outcome only)
#   N1-N5  pure noise
# Adjusting for instruments adds no bias reduction but pushes propensity
# scores towards 0 and 1, which inflates the variance of IPW-type estimators.
# C-TMLE chooses which covariates enter the propensity score model using the
# data, so it should behave like an analyst who knew the true roles.

using DataFrames
using CategoricalArrays
using Random
using Statistics
using StableRNGs
using LogExpFunctions
using TMLE

const TRUE_ATE = 2.0

const CONFOUNDERS  = [:W1, :W2, :W3]
const INSTRUMENTS  = [:Z1, :Z2, :Z3]
const PREDICTORS   = [:X1, :X2, :X3]
const NOISE        = [:N1, :N2, :N3, :N4, :N5]
const ALL_COVARIATES = vcat(CONFOUNDERS, INSTRUMENTS, PREDICTORS, NOISE)

"""
    simulate_data(rng; n=1000, confounding=1.0, instrument=1.0)

Simulate one observational dataset. `instrument` controls how strongly the
instruments drive treatment, `confounding` how strongly the confounders drive
both treatment and outcome. The true average treatment effect is always
`TRUE_ATE`. Returns a named tuple `(data, propensity)` where `propensity` is the
true probability of treatment for each row.
"""
function simulate_data(rng; n=1000, confounding=1.0, instrument=1.0)
    W = randn(rng, n, 3)
    Z = randn(rng, n, 3)
    X = randn(rng, n, 3)
    N = randn(rng, n, 5)

    linear_predictor = confounding .* 0.5 .* vec(sum(W; dims=2)) .+
                       instrument .* 0.8 .* vec(sum(Z; dims=2))
    propensity = logistic.(linear_predictor)
    treated = rand(rng, n) .< propensity

    Y = 1.0 .+ TRUE_ATE .* treated .+
        confounding .* vec(sum(W; dims=2)) .+
        vec(sum(X; dims=2)) .+
        randn(rng, n)

    data = DataFrame(A = categorical(treated), Y = Y)
    for (block, names) in ((W, CONFOUNDERS), (Z, INSTRUMENTS), (X, PREDICTORS), (N, NOISE))
        for (j, name) in enumerate(names)
            data[!, name] = block[:, j]
        end
    end
    return (data = data, propensity = propensity)
end

# What a careful analyst would write down: adjust for everything available.
const Ψ_all = ATE(
    outcome = :Y,
    treatment_values = (A = (case = true, control = false),),
    treatment_confounders = (A = ALL_COVARIATES,)
)

# An oracle that knows the true roles: confounders in the propensity score,
# outcome predictors only in the outcome model.
const Ψ_oracle = ATE(
    outcome = :Y,
    treatment_values = (A = (case = true, control = false),),
    treatment_confounders = (A = CONFOUNDERS,),
    outcome_extra_covariates = PREDICTORS
)

"""
    estimators()

Fresh estimator objects for one analysis. Collaborative strategies carry state,
so they are rebuilt for every dataset.
"""
estimators() = [
    ("One-step (AIPW)",               Ose(),                                                     Ψ_all),
    ("TMLE (unweighted)",             Tmle(weighted = false),                                    Ψ_all),
    ("TMLE (weighted)",               Tmle(),                                                    Ψ_all),
    ("C-TMLE (greedy)",               Tmle(collaborative_strategy = GreedyStrategy(patience = 5)), Ψ_all),
    ("C-TMLE (adaptive correlation)", Tmle(collaborative_strategy = AdaptiveCorrelationStrategy(patience = 5)), Ψ_all),
    ("Oracle TMLE",                   Tmle(),                                                    Ψ_oracle),
]

const ESTIMATOR_ORDER = [
    "Naive difference in means", "One-step (AIPW)", "TMLE (unweighted)", "TMLE (weighted)",
    "C-TMLE (greedy)", "C-TMLE (adaptive correlation)", "Oracle TMLE",
]

"Unadjusted comparison of treated and untreated means, with a Welch-type interval."
function naive_estimate(data)
    a = unwrap.(data.A)
    y1, y0 = data.Y[a], data.Y[.!a]
    est = mean(y1) - mean(y0)
    se = sqrt(var(y1) / length(y1) + var(y0) / length(y0))
    return (estimator = "Naive difference in means", estimate = est,
            lower = est - 1.96se, upper = est + 1.96se, seconds = 0.0)
end

"""
    estimate_all(data; verbosity=0)

Run every estimator on one dataset. Returns a DataFrame with one row per
estimator: point estimate, 95% confidence interval and run time. An estimator
that fails returns NaN rather than stopping a whole simulation.
"""
function estimate_all(data; verbosity=0)
    rows = NamedTuple[naive_estimate(data)]
    for (name, estimator, Ψ) in estimators()
        t0 = time()
        row = try
            result, _ = estimator(Ψ, data; verbosity = verbosity)
            lower, upper = confint(OneSampleTTest(result))
            (estimator = name, estimate = result.estimate, lower = lower, upper = upper,
             seconds = time() - t0)
        catch err
            verbosity > 0 && @warn "$name failed" exception = err
            (estimator = name, estimate = NaN, lower = NaN, upper = NaN, seconds = time() - t0)
        end
        push!(rows, row)
    end
    return DataFrame(rows)
end

"Bias, spread, error, coverage and interval width for each estimator and setting."
function summarise(results)
    ok = filter(r -> isfinite(r.estimate), results)
    g = groupby(ok, [:instrument, :estimator])
    s = combine(g,
        :estimate => (e -> mean(e) - TRUE_ATE) => :bias,
        :estimate => (e -> median(e) - TRUE_ATE) => :median_bias,
        :estimate => std => :sd,
        :estimate => (e -> sqrt(mean((e .- TRUE_ATE) .^ 2))) => :rmse,
        [:lower, :upper] => ((l, u) -> mean(l .<= TRUE_ATE .<= u)) => :coverage,
        [:lower, :upper] => ((l, u) -> median(u .- l)) => :median_ci_width,
        :seconds => mean => :mean_seconds,
        nrow => :n_ok,
    )
    s.estimator = categorical(s.estimator; levels = ESTIMATOR_ORDER, ordered = true)
    return sort(s, [:instrument, :estimator])
end

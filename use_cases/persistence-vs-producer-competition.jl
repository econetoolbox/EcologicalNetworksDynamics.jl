import AlgebraOfGraphics: set_aog_theme!
import ColorSchemes: get, viridis
import Statistics: mean, std
using CairoMakie
using DataFrames
using EcologicalNetworksDynamics

# Define global community parameters.
S = 20 # Species richness.
bodymass = BodyMass(; Z = 100) # Z = predator-prey bodymass ratio.
K = 1.0 # Producer carrying capacity.
aii = 1.0 # Intraspecific competition among producers.
extinction_threshold = 1e-6 # Set biomass threshold to consider a species extinct.
n_replicates = 100 # Number of food web replicates for each parameter combination.
aij_values = 0.8:0.05:1.2 # Interspecific competition values.
C_values = [0.05, 0.1, 0.2] # Connectance values.
tol_C = 0.01 # Tolerance on connectance when generating foodweb with the nichemodel.
t = 2_000 # Simulation length.
verbose = false # Do not show '@info' messages during simulation run.

"""
Standardize total carrying capacity `K` for the number of producers in the `foodweb`
and interspecific competition among producers `a_ij`.
"""
standardize_K(n_producers, K, aij) = K * (1 + (aij * (n_producers - 1))) / n_producers

# Main simulation loop.
# Each thread writes in its own DataFrame. Merge them at the end of the loop.
dfs = [DataFrame() for _ in eachindex(C_values)] # Fill the vector with empty DataFrames.
Threads.@threads for i in eachindex(C_values) # Parallelize on connctance values.
    C = C_values[i]
    df_thread = DataFrame(; C = Float64[], aij = Float64[], persistence = Float64[])
    for j in 1:n_replicates
        foodweb = Foodweb(:niche; S, C, tol_C)
        base_model = default_model(foodweb, bodymass; without = ProducerGrowth)
        for aij in aij_values
            logistic_growth = LogisticGrowth(;
                producers_competition = (diag = aii, offdiag = aij),
                K = standardize_K(base_model.producers.number, K, aij),
            )
            m = base_model + logistic_growth # Update logistic growth component.
            B0 = rand(S) # Initial biomass.
            solution = simulate(m, B0, t; extinction_threshold)
            push!(df_thread, [C, aij, persistence(solution[end])])
            @info "C = $C, foodweb = $j, aij = $aij: done."
        end
    end
    dfs[i] = df_thread
end
@info "All simulations done."
df = reduce(vcat, dfs)

# Compute the mean persistence and the 95% confidence interval (`ci95`)
# for each (C, αij) combination.
groups = groupby(df, [:C, :aij])
df_processed = combine(
    groups,
    :persistence => mean,
    :persistence => (x -> 1.96 * std(x) / sqrt(length(x))) => :ci95,
)

# Plot mean species persistence with its confidence interval
# versus αij for each connectance value.
set_aog_theme!()
fig = Figure()
ax = Axis(
    fig[2, 1];
    xlabel = "Interspecific producer competition, αᵢⱼ",
    ylabel = "Species persistence",
)
curves = []
colors = [get(viridis, val) for val in LinRange(0, 1, length(C_values))]
for (C, color) in zip(C_values, colors)
    df_extract = df_processed[df_processed.C.==C, :]
    x = df_extract.aij
    y = df_extract.persistence_mean
    ci = df_extract.ci95
    sl = scatterlines!(x, y; color = color, markercolor = color)
    errorbars!(x, y, ci; color, whiskerwidth = 5)
    push!(curves, sl)
end
Legend(
    fig[1, 1],
    curves,
    ["C = $C" for C in C_values];
    orientation = :horizontal,
    tellheight = true, # Adjust top subfigure height to legend height.
    tellwidth = false, # Do not adjust bottom subfigure width to legend width.
)
# To save the figure, uncomment and execute the line below.
save("persistence-vs-producer-competition.png", fig; size = (450, 300), px_per_unit = 3)

# Added for revisions.
# Compute mean number of producers for each connectance value.
df_prod = DataFrame(; C = Float64[], n_producers = Int64[])
for C in C_values
    df_thread = DataFrame(; C = Float64[], aij = Float64[], persistence = Float64[])
    for j in 1:n_replicates
        foodweb = Foodweb(:niche; S, C, tol_C)
        base_model = default_model(foodweb, bodymass; without = ProducerGrowth)
        push!(df_prod, [C, base_model.n_producers])
    end
end
combine(groupby(df_prod, :C), :n_producers => mean)

# The "Solution" object carries a lot of meaning
# since it represents the state of some ecological model after some dynamics.
# TODO: should it be newtyped to feature `sol.property` like the model?

# ==========================================================================================
# Basic info.

"""
    model(sol::Solution)

Retrieve a copy of the model used for this simulation.
"""
model(sol::Solution) = copy(sol.prob.p.model) # (copy to not leak aliases)
export model

"""
    species_indices(sol::Solution)

Retrieve the correct indices to extract species-related data from simulation output.
"""
function species_indices(sol::Solution)
    m = model(sol)
    1:(m.n_species)
end
export species_indices

"""
    nutrients_indices(sol::Solution)

Retrieve the correct indices to extract nutrients-related data from simulation output.
"""
function nutrients_indices(sol::Solution)
    m = model(sol)
    N = m.n_nutrients
    S = m.n_species
    (S+1):(S+N)
end
export nutrients_indices

# ==========================================================================================
# Extinctions and their effects on topology.

"""
    extinctions(sol::Solution, date = nothing)

Extract list of extinct species indices and their extinction dates
from the solution returned by `simulate()`.
If a simulation date is provided,
restrict to the list of species extinct in the simulation at this date.
"""
function extinctions(sol::Solution, date::Option{Number} = nothing)
    if isnothing(date)
        date = Inf
    else
        s, e = sol.t[1], sol.t[end]
        s <= date <= e || argerr("Invalid date for a simulation in t = [$s, $e]: $date.")
    end
    Dict(i => d for (i, d) in Internals.get_extinct_species(sol) if d <= date)
end
export extinctions

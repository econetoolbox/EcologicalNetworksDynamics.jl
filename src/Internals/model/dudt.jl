"""
    dudt!(du, u, p, _)

Compute the species and nutrient (when relevant) abundance derivatives `du`,
given the abundances `u` and the model `p`.
The last silent argument is the time at which is evaluated the derivatives
and is a requirement of DifferentialEquations.
"""
function dudt!(du, u, p, _)
    params, extinct_sp = p
    S = richness(params)
    B = u[species_indices(params)]
    response_matrix = params.functional_response(B, params.network)
    network = params.network
    growth = fill(0.0, S) # Vector of producer growths.

    # Compute species biomass dynamics.
    for i in species_indices(params)
        growth[i] = params.producer_growth(i, u, params)
        eating, being_eaten = consumption(i, B, params, response_matrix)
        metabolism_loss = metabolic_loss(i, B, params)
        natural_death = natural_death_loss(i, B, params)
        net_growth_rate = growth[i] + eating - metabolism_loss
        net_growth_rate = effect_competition(net_growth_rate, i, B, network)
        du[i] = net_growth_rate - being_eaten - natural_death
    end

    # Compute nutrient abundance dynamics.
    for (i_nutrient, i_u) in enumerate(nutrient_indices(params))
        n = u[i_u]
        du[i_u] = nutrient_dynamics(params, B, i_nutrient, n, growth)
    end

    # Avoid zombie species by forcing extinct biomasses to zero.
    # https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/65
    for sp in keys(extinct_sp)
        u[sp] = 0.0
    end
end

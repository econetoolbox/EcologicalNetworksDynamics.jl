# EFFECT OF NON-TROPHIC INTERACTIONS ON MODEL PARAMETERS

"""
Effect of competition on the net growth rate.
"""
function effect_competition(G_net, i, B, network::MultiplexNetwork)
    isproducer(i, network) || return G_net
    c0 = network.layers[:competition].intensity
    competitors = network.layers[:competition].A[:, i] # sp competing for space with sp i
    δG_net = c0 * sum(B .* competitors)
    network.layers[:competition].f(G_net, δG_net)
end
effect_competition(G_net, _, _, _::FoodWeb) = G_net

"""
Effect of facilitation on intrinsic growth rate.
"""
function effect_facilitation(r, i, B, network::MultiplexNetwork)
    f0 = network.layers[:facilitation].intensity
    facilitating_species = network.layers[:facilitation].A[:, i]
    δr = f0 * sum(B .* facilitating_species)
    network.layers[:facilitation].f(r, δr)
end

"""
Effect of refuge on attack rate.
"""
function effect_refuge(aᵣ, B, network::MultiplexNetwork)
    r0 = network.layers[:refuge].intensity
    r0 > 0 || return aᵣ # r0 = 0 ⇒ no effect of refuge
    A_refuge = network.layers[:refuge].A
    n_links(A_refuge) > 0 || return aᵣ # no refuge links ⇒ no effect of refuge
    f_refuge = network.layers[:refuge].f
    S = richness(A_refuge)
    prey = preys(aᵣ)
    aᵣ_refuge = zeros(eltype(B), S, S)
    for i in prey
        providing_refuge = A_refuge[:, i] # species providing a refuge to 'prey'
        δaᵣ = r0 * sum(providing_refuge .* B)
        for j in aᵣ[:, i].nzind
            aᵣ_refuge[j, i] = f_refuge(aᵣ[j, i], δaᵣ)
        end
    end
    aᵣ_refuge
end

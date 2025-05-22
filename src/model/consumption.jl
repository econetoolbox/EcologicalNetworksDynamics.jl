#=
Consumption
=#
"""
Allee effect modifier for assimilation efficiency
"""
function allee_efficiency(B::Vector{Float64}, β::Real)

    # Extinct species give a modifier of NaN which is crashing, this changes it to a real number :)  
    temp_B = deepcopy(B) # But we don't want to change the actual biomass values
    temp_B[temp_B .== 0] .= 1 # Set it from 0 to 1 

    modifier = temp_B ./ (β .+ temp_B)
    modifier[modifier .== 0] .= 1

    return modifier
end

"""
Compute consumption terms of ODEs.
"""
function consumption(i, B, p::ModelParameters, fᵣmatrix)
    # Dispatch to correct method depending on functional response type.
    consumption(p.functional_response, i, B, p::ModelParameters, fᵣmatrix)
end

function consumption(::BioenergeticResponse, i, B, params::ModelParameters, fᵣmatrix)
    # Set up
    net = params.network
    prey = preys_of(i, net)
    pred = predators_of(i, net)
    x = params.biorates.x # metabolic rate
    y = params.biorates.y # max. consumption
    e = params.allee_effect.addallee && params.allee_effect.target == :e ? params.biorates.e .* allee_efficiency((B[1:S] ./ (M .^ params.allee_effect.exponent)), params.allee_effect.β) : params.biorates.e # assimilation efficiency

    # Compute consumption terms
    eating = x[i] * y[i] * B[i] * sum(fᵣmatrix[i, prey])
    being_eaten = sum(x[pred] .* y[pred] .* B[pred] .* fᵣmatrix[pred, i] ./ e[pred, i])
    eating, being_eaten
end

# Code generation version(s) (raw) (↑ ↑ ↑ DUPLICATED FROM ABOVE ↑ ↑ ↑).
# (update together as long as the two coexist)
eating(i, p::ModelParameters) = eating(p.functional_response, i, p) # (dispatch)
function eating(::BioenergeticResponse, i, parms::ModelParameters)
    preys = preys_of(i, parms.network)
    B_i = :(B[$i])
    x_i = parms.biorates.x[i]
    y_i = parms.biorates.y[i]
    F_ip = [Symbol("F_$(i)_$(p)") for p in preys]
    (x_i == 0 || y_i == 0 || length(preys) == 0) && return 0 #  Just to clarify expressions.
    :($x_i * $y_i * $B_i * xp_sum([:f_ip], $[F_ip], :(f_ip)))
end
being_eaten(i, p::ModelParameters) = being_eaten(p.functional_response, i, p) # (dispatch)
function being_eaten(::BioenergeticResponse, i, parms::ModelParameters)
    preds = predators_of(i, parms.network)
    x = parms.biorates.x[preds]
    y = parms.biorates.y[preds]
    e_pi = [parms.biorates.e[p, i] for p in preds]
    F_pi = [Symbol("F_$(p)_$(i)") for p in preds]
    :(xp_sum(
        [:p, :xp, :yp, :e_pi, :f_pi],
        $[preds, x, y, e_pi, F_pi],
        :(xp * yp * B[p] * f_pi / e_pi),
    ))
end

# Code generation version (compact):
# Explain how to efficiently construct all values of eating/being_eaten,
# and provide the additional/intermediate data needed.
# This code is responsible to *initialize* all dB[i] values.
# It also features `natural_death_loss`
# because it contains one full iteration over 1:S.
# This is about to change in upcoming refactorization of the boost option.
consumption(p::ModelParameters, ::Symbol) = consumption(p.functional_response, p) # (dispatch)
function consumption(::BioenergeticResponse, parms::ModelParameters)

    # Basic informations made available as variables in the generated code.
    S = richness(parms.network)
    data = Dict(
        :x => parms.biorates.x,
        :y => parms.biorates.y,
        # Scratch space to calculate intermediate values.
        :Σ_res => zeros(S),
        :Σ_cons => zeros(S),
    )
    # Flatten the e matrix with the same 'ij' indexing.
    cons, res = findnz(parms.network.A)
    data[:e] = [parms.biorates.e[i, j] for (i, j) in zip(cons, res)]
    data[:d] = parms.biorates.d

    # The following code relies on the following variables
    # being already created by the functional response generated code:
    #   S
    #   F
    #   nonzero_links
    code = [
        :(
            # Only nonzero entries contribute to these terms.
            # Calculate their contributions first:
            for (ij, (i, j)) in enumerate(zip(nonzero_links...))
                ir, i, r = ij, i, j #  i is focal, r is resource of i
                Σ_res[i] += F[ir]
                ci, c, i = ij, i, j #  i is focal, c is consumer of i
                Σ_cons[i] += x[c] * y[c] * B[c] * F[ci] / e[ci]
            end
        ),
        :(
            # Then the full actual terms.
            # This is the first and only full iteration over 1:S.
            # Take this opportunity to *initialize* every dB[i].
            for i in 1:S
                eating = B[i] * x[i] * y[i] * Σ_res[i]
                being_eaten = Σ_cons[i]
                natural_death = d[i] * B[i]
                # (Re-)initialization of dB[i] happens here.
                dB[i] = eating - being_eaten - natural_death
                # Reset scratch space for next time.
                Σ_res[i] = 0
                Σ_cons[i] = 0
                # /!\ Take this opportunity to also reset producers competition.
                # This should change in future evolution in :compact generated code.
                s[i] = 0
            end
        ),
    ]

    code, data
end

function consumption(
    ::Union{ClassicResponse,LinearResponse},
    i,
    B,
    params::ModelParameters,
    fᵣmatrix,
)
    # Set up
    net = params.network
    prey = preys_of(i, net)
    pred = predators_of(i, net)
    e = params.biorates.e

    # Compute consumption terms
    eating = B[i] * sum(e[i, prey] .* fᵣmatrix[i, prey])
    being_eaten = sum(B[pred] .* fᵣmatrix[pred, i])
    eating, being_eaten
end
# Code generation version(s) (raw) (↑ ↑ ↑ DUPLICATED FROM ABOVE ↑ ↑ ↑).
# (update together as long as the two coexist)
function eating(::Union{ClassicResponse,LinearResponse}, i, parms::ModelParameters)
    preys = preys_of(i, parms.network)
    (length(preys) == 0) && return 0 #  Just to clarify expressions.
    B_i = :(B[$i])
    E_ip = parms.biorates.e[i, preys]
    F_ip = [Symbol("F_$(i)_$(p)") for p in preys]
    :($B_i * xp_sum([:e_ip, :f_ip], $[E_ip, F_ip], :(e_ip * f_ip)))
end
function being_eaten(::Union{ClassicResponse,LinearResponse}, i, parms::ModelParameters)
    preds = predators_of(i, parms.network)
    F_pi = [Symbol("F_$(p)_$(i)") for p in preds]
    :(xp_sum([:p, :f_pi], $[preds, F_pi], :(B[p] * f_pi)))
end
# Code generation version (compact):
# Explain how to efficiently construct all values of eating/being_eaten,
# and provide the additional/intermediate data needed.
# This code is responsible to *initialize* all dB[i] values.
# It also features `natural_death_loss`
# because it contains one full iteration over 1:S.
# This is about to change in upcoming refactorization of the boost option.
function consumption(::Union{ClassicResponse,LinearResponse}, parms::ModelParameters)

    # Basic informations made available as variables in the generated code.
    S = richness(parms.network)
    data = Dict(
        # Scratch space to calculate intermediate values.
        :Σ_res => zeros(S),
        :Σ_cons => zeros(S),
    )
    # Flatten the e matrix with the same 'ij' indexing.
    cons, res = findnz(parms.network.A)
    data[:e] = [parms.biorates.e[i, j] for (i, j) in zip(cons, res)]
    data[:d] = parms.biorates.d

    # The following code relies on the following variables
    # being already created by the functional response generated code:
    #   S
    #   F
    #   nonzero_links
    code = [
        :(
            # Only nonzero entries contribute to these terms.
            # Calculate their contributions first:
            for (ij, (i, j)) in enumerate(zip(nonzero_links...))
                ir, i, r = ij, i, j #  i is focal, r is resource of i
                Σ_res[i] += e[ir] * F[ir]
                ci, c, i = ij, i, j #  i is focal, c is consumer of i
                Σ_cons[i] += B[c] * F[ci]
            end
        ),
        :(
            # Then the full actual terms.
            # This is the first and only full iteration over 1:S.
            # Take this opportunity to *initialize* every dB[i].
            for i in 1:S
                eating = B[i] * Σ_res[i]
                being_eaten = Σ_cons[i]
                natural_death = d[i] * B[i]
                # (Re-)initialization of dB[i] happens here.
                dB[i] = eating - being_eaten - natural_death
                # Reset scratch space for next time.
                Σ_res[i] = 0
                Σ_cons[i] = 0
                # /!\ Take this opportunity to also reset producers competition.
                # This should change in future evolution in :compact generated code.
                s[i] = 0
            end
        ),
    ]

    code, data
end


function stoch_consumption(i, B, p::ModelParameters, fᵣmatrix)  #  (dispatch)
    stoch_consumption(p.functional_response, i, B, p, fᵣmatrix)
end
function stoch_consumption(::BioenergeticResponse, i, B, params::ModelParameters, fᵣmatrix)

    # Set up
    foodweb = convert(FoodWeb, params.network)
    prey = preys_of(i, foodweb) # resource of species i
    pred = predators_of(i, foodweb) # consumer of species i
    S = richness(params.network)

    stochcons = intersect(pred, params.stochasticity.stochconsumers)
    determcons = setdiff(pred, stochcons)

    x = zeros(S)
    for i in 1:S
        if i ∈ params.stochasticity.stochconsumers
            x[i] = B[S+first(findall(x -> x == i, params.stochasticity.stochspecies))]
        else
            x[i] = params.biorates.x[i] # metabolic rate
        end
    end

    y = params.biorates.y # max. consumption
    e = params.allee_effect.addallee && params.allee_effect.target == :e ? params.biorates.e .* allee_efficiency(B[1:S], params.allee_effect.β) : params.biorates.e # assimilation efficiency

    # Compute consumption terms
    eating = x[i] * y[i] * B[i] * sum(fᵣmatrix[i, prey])
    being_eaten_by_deterministic = sum(
        x[determcons] .* y[determcons] .* B[determcons] .* fᵣmatrix[determcons, i] ./
        e[determcons, i],
    )
    being_eaten_by_stochastic = sum(
        B[S.+findall(x -> x ∈ stochcons, params.stochasticity.stochspecies)] .*
        y[stochcons] .* B[stochcons] .* fᵣmatrix[stochcons, i] ./ e[stochcons, i],
    )
    being_eaten = being_eaten_by_deterministic + being_eaten_by_stochastic

    eating, being_eaten
end


function stoch_consumption(
    ::Union{ClassicResponse,LinearResponse},
    i,
    B,
    params::ModelParameters,
    fᵣmatrix,
)
    # Set up
    net = params.network
    prey = preys_of(i, net)
    pred = predators_of(i, net)
    e = params.biorates.e

    # Compute consumption terms
    eating = B[i] * sum(e[i, prey] .* fᵣmatrix[i, prey])
    being_eaten = sum(B[pred] .* fᵣmatrix[pred, i])
    eating, being_eaten
end # literally same as deterministic
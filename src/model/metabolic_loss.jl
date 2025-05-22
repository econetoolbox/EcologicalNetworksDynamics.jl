#=
Metabolic losses
=#

metabolic_loss(i, B, params::ModelParameters) = params.biorates.x[i] * B[i]
# Code generation version (raw) (↑ ↑ ↑ DUPLICATED FROM ABOVE ↑ ↑ ↑).
# (update together as long as the two coexist)
function metabolism_loss(i, parms::ModelParameters)
    B_i = :(B[$i])
    x_i = parms.biorates.x[i]
    (x_i == 0) && return 0 #  Just to simplify expressions.
    :($x_i * $B_i)
end

# Code generation version (compact):
# Explain how to efficiently construct all values of eating/being_eaten,
# and provide the additional/intermediate data needed.
# This code assumes that dB[i] has already been *initialized*.
function metabolism_loss(parms::ModelParameters, ::Symbol)

    # Pre-calculate skips over lossless species.
    data = Dict(:loss => [(i, x) for (i, x) in enumerate(parms.biorates.x) if x != 0])

    code = [:(
        for (i, x_i) in loss #  (skips over null terms)
            dB[i] -= x_i * B[i]
        end
    )]

    code, data
end

natural_death_loss(i, B, params::ModelParameters) = params.biorates.d[i] * B[i]
# Code generation version (raw) (↑ ↑ ↑ DUPLICATED FROM ABOVE ↑ ↑ ↑).
function natural_death_loss(i, parms::ModelParameters)
    B_i = :(B[$i])
    d_i = parms.biorates.d[i]
    :($d_i * $B_i)
end
# Code generation version (compact) is integrated to `consumption`
# because it needs one full iteration over 1:S.
# This is about to change in upcoming refactorization of the boost option.


function allee_death_loss(i, B, params::ModelParameters)
    d_i = params.biorates.d[i]
    β = params.allee_effect.β
    μ = params.allee_effect.μ
    Mᵢ = params.network.M[i]
    expo = params.allee_effect.exponent
    Bᵢ = B[i]
    Nᵢ = Bᵢ / (Mᵢ ^ expo)

    (Bᵢ * ((μ * β) / (β + Nᵢ))) + (d_i * Bᵢ)
end

function stoch_metabolic_loss(i, B, params::ModelParameters)
    S = richness(params.network)
    if i ∈ params.stochasticity.stochconsumers
        xᵢ = B[S+first(findall(x -> x == i, params.stochasticity.stochspecies))] # metabolic rate of species i
        Bᵢ = B[i] # biomass of species i
        xᵢ * Bᵢ
    else
        xᵢ = params.biorates.x[i] # metabolic rate of species i
        Bᵢ = B[i] # biomass of species i
        xᵢ * Bᵢ
    end
end

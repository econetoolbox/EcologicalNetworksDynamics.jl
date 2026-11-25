module ProducerCompetitionDef

using EcologicalNetworksDynamics.Interface:
    EN, SL, IT, @bp_construct, Model, argerr, Adjacency, Blueprint, @alias
using EcologicalNetworksDynamics.KwargsHelpers
using LinearAlgebra

const s, S = SL.EdgeField(:inter_producer, :competition)
SL.name_variants(::S) = (
    :producer_competition,
    :producer_competition,
    :ProducerCompetition,
    :ProducerCompetition,
    :alpha,
)
SL.type(::S) = Float64
IT.early_check(::S, alpha::Real) = IT.non_negative(Float64, alpha)

# ==========================================================================================
"Build from diagonal-symmetric matrix: 1 value for self-competition, 1 for inter-producers."
mutable struct Diagonal <: Blueprint
    diag::Float64 # Diagonal value.
    off::Float64 # Off-diagonal values.
    @bp_construct Diagonal
end
IT.register_blueprint(Diagonal, "diagonal/off-diagonal values"; s, depends = [EN.Foodweb])

function IT.construct(::Type{Diagonal}, a...; kw...)
    @kwargs_helpers kw
    alias!(:diag, :diagonal, :d)
    alias!(:off, :offdiagonal, :offdiag, :o, :rest, :nondiagonal, :nd)
    no_positional(a)
    d = take_or!(:diag, 1.0)
    o = take_or!(:off, 0.0)
    no_unused_arguments()
    IT.early_check.((s,), (d, o))
end
IT.bp_early_check(bp::Diagonal) = IT.early_check.((s,), (bp.diag, bp.off))

function IT.expand!(md::Model, ::Diagonal, (diag, off))
    n = md.producers.number
    alpha = diag * I(n) + off * (ones((n, n)) - I(n))
    IT.expand!(md, s, alpha)
end
# ==========================================================================================

const ProducerCompetition, _ProducerCompetition =
    IT.define_web_field_component(EN, s; blueprints = [Diagonal])

# Single-entry constructor.
function (::_ProducerCompetition)(alpha = nothing; kwargs...)
    if isempty(kwargs)
        isnothing(alpha) && argerr("No input provided to specify producer competition.")
        return IT.try_convert(alpha,
            Float64 => ProducerCompetition.Flat,
            Vector{Float64} => ProducerCompetition.Raw,
            Matrix{Float64} => ProducerCompetition.Matrix,
            Adjacency{<:Any,Float64} => ProducerCompetition.Adjacency,
        )
    end
    isnothing(alpha) ||
        argerr("No need to provide both alpha matrix and keyword arguments.")
    ProducerCompetition.Diagonal(; kwargs...)
end

@alias producers.competition producer_competition

end
local ProducerCompetition, _ProducerCompetition # (reassure JuliaLS)
export ProducerCompetition

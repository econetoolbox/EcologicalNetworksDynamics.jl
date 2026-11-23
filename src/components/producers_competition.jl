module ProducersCompetitionDef

using EcologicalNetworksDynamics.Interface:
    EN, SL, IT, @bp_construct, Model, argerr, Adjacency, Blueprint, @alias
using EcologicalNetworksDynamics.KwargsHelpers
using LinearAlgebra

const s, S = SL.EdgeField(:inter_producers, :competition)
SL.name_variants(::S) = (
    :producers_competition,
    :producers_competition,
    :ProducersCompetition,
    :ProducersCompetition,
    :alpha,
)
SL.type(::S) = Float64
SL.is_sparse(::S) = false # All producer-to-producer edges are reified.
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

const ProducersCompetition, _ProducersCompetition =
    IT.define_web_field_component(EN, s; blueprints = [Diagonal])

# Single-entry constructor.
function (::_ProducersCompetition)(alpha = nothing; kwargs...)
    if isempty(kwargs)
        isnothing(alpha) && argerr("No input provided to specify producers competition.")
        return IT.try_convert(alpha,
            Float64 => ProducersCompetition.Flat,
            Vector{Float64} => ProducersCompetition.Raw,
            Matrix{Float64} => ProducersCompetition.Matrix,
            Adjacency{<:Any,Float64} => ProducersCompetition.Adjacency,
        )
    end
    isnothing(alpha) ||
        argerr("No need to provide both alpha matrix and keyword arguments.")
    ProducersCompetition.Diagonal(; kwargs...)
end

@alias producers.competition producers_competition

end
local ProducersCompetition, _ProducersCompetition # (reassure JuliaLS)
export ProducersCompetition

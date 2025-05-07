# Set or generate producer competition rates
# for every producer-to-producer link in the model.

# Mostly duplicated from Efficiency.

# (reassure JuliaLS)
(false) && (local ProducersCompetition, _ProducersCompetition)

# ==========================================================================================
module ProducersCompetition_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Foodweb, _Foodweb
import .EN: Topologies as G

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    alpha::SparseMatrix{Float64}
    Raw(alpha) = new(@tographdata(alpha, SparseMatrix{Float64}))
end
@blueprint Raw "sparse matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.alpha)
check(alpha, ref = nothing) = check_value(>=(0), alpha, ref, :alpha, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; alpha) = bp
    A = @ref raw.producers.matrix
    @check_template alpha A "producers links"
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.alpha)
function expand!(raw, alpha)
    # Only add trophic edges where there are non-*missing* values (not *non-zero*).
    # This way, user can modify zero values later if they were non-missing.
    sources, targets, _ = findnz(alpha)
    mask = spzeros(Bool, size(alpha))
    for (src, tgt) in zip(sources, targets)
        mask[src, tgt] = true
    end
    raw._scratch[:producers_competition] = alpha
    raw._scratch[:producers_competition_mask] = mask
    g = raw._topology
    ety = :producers_competition
    G.add_edge_type!(g, ety)
    G.add_edges_within_node_type!(g, :species, ety, mask)
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    alpha::Float64
end
@blueprint Flat "uniform value" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.alpha)
function F.expand!(raw, bp::Flat)
    (; alpha) = bp
    A = @ref raw.producers.matrix
    alpha = to_template(alpha, A)
    expand!(raw, alpha)
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    alpha::@GraphData Adjacency{Float64}
    Adjacency(alpha) = new(@tographdata(alpha, Adjacency{Float64}))
end
@blueprint Adjacency "[producer => [producer => competition]] adjacency list"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.alpha)
function F.late_check(raw, bp::Adjacency)
    (; alpha) = bp
    index = @ref raw.species.index
    A = @ref raw.producers.matrix
    @check_list_refs alpha "producers link" index template(A)
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    alpha = to_sparse_matrix(bp.alpha, index, index)
    expand!(raw, alpha)
end

#-------------------------------------------------------------------------------------------
# From a diagonal symmetric: 1 value for self-competition, 1 value for inter-producers.

mutable struct Diagonal <: Blueprint
    diag::Float64 # Diagonal values.
    off::Float64 # Off-diagonal values.
    Diagonal(d, o = 0) = new(d, o)
    function Diagonal(; kwargs...)
        @kwargs_helpers kwargs
        alias!(:diag, :diagonal, :d)
        alias!(:off, :offdiagonal, :offdiag, :o, :rest, :nondiagonal, :nd)
        d = take_or!(:diag, 1.0)
        o = take_or!(:off, 0.0)
        no_unused_arguments()
        new(d, o)
    end
end
@blueprint Diagonal "diagonal/off-diagonal values"
export Diagonal

function F.early_check(bp::Diagonal)
    check(bp.diag, (:diag,))
    check(bp.off, (:off,))
end

function F.expand!(raw, bp::Diagonal)
    (; diag, off) = bp
    S = @get raw.richness
    A = @ref raw.producers.matrix
    alpha = spzeros((S, S))
    sources, targets, _ = findnz(A)
    for (i, j) in zip(sources, targets)
        alpha[i, j] = (i == j) ? diag : off
    end
    expand!(raw, alpha)
end

end

# ==========================================================================================
# Component and generic constructors.

@component begin
    ProducersCompetition{Internal}
    requires(Foodweb)
    blueprints(ProducersCompetition_)
end
export ProducersCompetition

function (::_ProducersCompetition)(alpha = nothing; kwargs...)

    if isempty(kwargs)
        isnothing(alpha) && argerr("No input provided to specify producers competition.")
        alpha = @tographdata alpha {Scalar, SparseMatrix, Adjacency}{Float64}
        if alpha isa SparseMatrix
            ProducersCompetition.Raw(alpha)
        elseif alpha isa Real
            ProducersCompetition.Flat(alpha)
        else
            ProducersCompetition.Adjacency(alpha)
        end
    else
        isnothing(alpha) ||
            argerr("No need to provide both alpha matrix and keyword arguments.")
        ProducersCompetition.Diagonal(; kwargs...)
    end

end

@propspace producers.competition

@expose_data edges begin
    property(producers.competition.matrix)
    depends(ProducersCompetition)
    @species_index
    ref(raw -> raw._scratch[:producers_competition])
    get(ProducersCompetitionMatrix{Float64}, sparse, "producers competition rates matrix")
    template(raw -> @ref raw.producers.competition.mask)
    write!((raw, rhs::Real, i, j) -> ProducersCompetition_.check(rhs, (i, j)))
end

@expose_data edges begin
    property(producers.competition.mask)
    depends(ProducersCompetition)
    @species_index
    ref(raw -> raw._scratch[:producers_competition_mask])
    get(ProducersCompetitionMask{Bool}, sparse, "producers competition edges mask")
end

function F.shortline(io::IO, model::Model, ::_ProducersCompetition)
    print(io, "Producers competition: ")
    showrange(io, model.producers.competition._matrix)
end

(false) && (local Topology, _Topology) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module Topology_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")
using .EN: Foodweb, _Foodweb

#-------------------------------------------------------------------------------------------
# From matrix.

mutable struct Raw <: Blueprint
    A::@GraphData SparseMatrix{Bool}
    Raw(A) = new(@tographdata(A, SparseMatrix{:bin}))
end
@blueprint Raw "sparse matrix"
export Raw

function F.early_check(bp::Raw)
    (m, n) = size(bp.A)
    m == n || checkfails("Links matrix should be squared, but dimensions are ($m, $n).")
end

function F.late_check(raw, bp::Raw)
    (; A) = bp
    P = @ref raw.interference.potential_links.matrix
    @check_template A P "potential interference link"
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.A)
expand!(raw, A) = expand_topology!(raw, :interference, A)

#-------------------------------------------------------------------------------------------
# From adjacency list.

mutable struct Adjacency <: Blueprint
    A::@GraphData Adjacency{:bin}
    Adjacency(A) = new(@tographdata(A, Adjacency{:bin}))
end
@blueprint Adjacency "[consumer => consumers] adjacency list"
export Adjacency

function F.late_check(raw, bp::Adjacency)
    (; A) = bp
    index = @ref raw.species.index
    P = @ref raw.interference.potential_links.matrix
    @check_list_refs A "consumer interference link" index template(P)
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    A = to_sparse_matrix(bp.A, index, index)
    expand!(raw, A)
end

#-------------------------------------------------------------------------------------------
# From random model.

mutable struct Random <: Blueprint
    L::Option{Int64}   # Conceptually a..
    C::Option{Float64} # .. runtime-checked enum.
    symmetry::Bool
    function Random(; kwargs...)
        L, C, symmetry = parse_random_links_arguments(:interference, kwargs)
        new(L, C, symmetry)
    end
end
@blueprint Random "random model"
export Random

F.early_check(bp::Random) = random_nti_early_check(bp)
function F.late_check(raw, bp::Random)
    nc = @get raw.consumers.number
    np = @get raw.preys.number
    Lmax = @get raw.interference.potential_links.number
    (; L) = bp
    if !isnothing(L)
        s(n) = n > 1 ? "s" : ""
        L > Lmax && checkfails("Cannot draw L = $L interference link$(s(L)) \
                                with these $nc consumer$(s(np)) \
                                and $np prey$(s(np)) (max: L = $Lmax).")
    end
end

function F.expand!(raw, bp::Random)
    A = random_links(raw, bp, Internals.potential_interference_links)
    expand!(raw, A)
end

end

# ==========================================================================================
# Component.

@component Topology{Internal} requires(Foodweb) blueprints(Topology_)
export Topology

function (::_Topology)(A = nothing; kwargs...)
    (isnothing(A) && isempty(kwargs)) &&
        argerr("No input given to specify interference links.")

    @kwargs_helpers kwargs
    (!isnothing(A) && given(:A)) && argerr("Redundant interference topology input.\n\
                                            Received both: $A\n\
                                            and          : $(take!(:A))")

    if !isnothing(A) || given(:A)
        A = given(:A) ? take!(:A) : A
        no_unused_arguments()

        A = @tographdata A {SparseMatrix, Adjacency}{:bin}
        if A isa AbstractMatrix
            Topology.Raw(A)
        else
            Topology.Adjacency(A)
        end

    else
        Topology.Random(; kwargs...)
    end

end

@expose_data edges begin
    property(interference.links.matrix)
    get(InterferenceLinks{Bool}, sparse, "interference link")
    ref(raw -> raw._scratch[:interference_links])
    @species_index
    depends(Topology)
end

@expose_data graph begin
    property(interference.links.number)
    ref_cached(raw -> sum(@ref raw.interference.links.matrix))
    get(raw -> @ref raw.interference.links.number)
    depends(Topology)
end

function F.shortline(io::IO, model::Model, ::_Topology)
    n = model.interference.links.number
    s(n) = n > 1 ? "s" : ""
    print(io, "Interference topology: $n link$(s(n))")
end

# Set or generate concentrations for every producer-to-nutrient link in the model.
#
# These links are not reified with anything akin to a *mask* yet,
# because there are stored densely in the legacy internals for now
# as a n_producers × n_nutrients matrix.
# TODO: this raises the question of the size of templated nodes/edges data:
#   - sparse, with the size of their compartment (eg. S with missing values for consumers).
#   - dense, with the size of the filtered compartment (eg. n_producers)
#     and then care must be taken while indexing it.
# Whether to use the first or the second option should be clarified
# on internals refactoring.

# (reassure JuliaLS)
(false) && (local Concentration, _Concentration)

# ==========================================================================================
module Concentration_
include("../blueprint_modules.jl")
include("../blueprint_modules_identifiers.jl")
import .EN: Foodweb, Nutrients

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    c::Matrix{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Raw(c, nt = Nutrients._Nodes) = new(@tographdata(c, Matrix{Float64}), nt)
end
F.implied_blueprint_for(bp::Raw, ::Nutrients._Nodes) = Nutrients.Nodes(size(bp.c)[2])
@blueprint Raw "producers × nutrients concentration matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.c)
check(c, ref = nothing) = check_value(>=(0), c, ref, :c, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; c) = bp
    P = @get raw.producers.number
    N = @get raw.nutrients.number
    @check_size c (P, N)
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.c)
expand!(raw, c) = raw._scratch[:nutrients_concentration] = c

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    c::Float64
end
@blueprint Flat "uniform concentration value" depends(Foodweb, Nutrients.Nodes)
export Flat

F.early_check(bp::Flat) = check(bp.c)
function F.expand!(raw, bp::Flat)
    P = @get raw.producers.number
    N = @get raw.nutrients.number
    expand!(raw, to_size(bp.c, (P, N)))
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    c::@GraphData Adjacency{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Adjacency(c, nt = Nutrients._Nodes) = new(@tographdata(c, Adjacency{Float64}), nt)
end
F.implied_blueprint_for(bp::Adjacency, ::Nutrients._Nodes) =
    Nutrients.Nodes(refspace_inner(bp.c))
@blueprint Adjacency "[producer => [nutrient => concentration]] map"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.c)
function F.late_check(raw, bp::Adjacency)
    (; c) = bp
    p_index = @ref raw.producers.sparse_index
    n_index = @ref raw.nutrients.index
    @check_list_refs c "producer trophic" (p_index, n_index) dense
end

function F.expand!(raw, bp::Adjacency)
    p_index = @ref raw.producers.dense_index
    n_index = @ref raw.nutrients.index
    c = to_dense_matrix(bp.c, p_index, n_index)
    expand!(raw, c)
end

end

# ==========================================================================================
@component begin
    Concentration{Internal}
    requires(Foodweb, Nutrients.Nodes)
    blueprints(Concentration_)
end
export Concentration

function (::_Concentration)(c)
    c = @tographdata c {Scalar, Matrix, Adjacency}{Float64}
    if c isa Real
        Concentration.Flat(c)
    elseif c isa AbstractMatrix
        Concentration.Raw(c)
    else
        Concentration.Adjacency(c)
    end
end

@expose_data edges begin
    property(nutrients.concentration)
    depends(Concentration)
    row_index(raw -> @ref raw.producers.dense_index)
    col_index(raw -> @ref raw.nutrients.index)
    ref(raw -> raw._scratch[:nutrients_concentration])
    get(Concentrations{Float64}, "producer-to-nutrient link")
    write!((raw, rhs::Real, i, j) -> Concentration_.check(rhs, (i, j)))
end

function F.shortline(io::IO, model::Model, ::_Concentration)
    print(io, "Nutrients concentration: ")
    showrange(io, model.nutrients._concentration)
end

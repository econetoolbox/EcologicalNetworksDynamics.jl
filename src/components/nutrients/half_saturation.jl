# Set or generate half saturations for every producer-to-nutrient link in the model.

# Mostly duplicated from HalfSaturation.

# (reassure JuliaLS)
(false) && (local HalfSaturation, _HalfSaturation)

# ==========================================================================================
module HalfSaturation_
include("../blueprint_modules.jl")
include("../blueprint_modules_identifiers.jl")
import .EN: Foodweb, Nutrients

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    h::Matrix{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Raw(h, nt = Nutrients._Nodes) = new(@tographdata(h, Matrix{Float64}), nt)
end
F.implied_blueprint_for(bp::Raw, ::Nutrients._Nodes) = Nutrients.Nodes(size(bp.h)[2])
@blueprint Raw "producers × nutrients half-saturation matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.h)
check(h, ref = nothing) = check_value(>=(0), h, ref, :h, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; h) = bp
    P = @get raw.producers.number
    N = @get raw.nutrients.number
    @check_size h (P, N)
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.h)
expand!(raw, h) = raw._scratch[:nutrients_half_saturation] = h

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    h::Float64
end
@blueprint Flat "uniform half-saturation value" depends(Foodweb, Nutrients.Nodes)
export Flat

F.early_check(bp::Flat) = check(bp.h)
function F.expand!(raw, bp::Flat)
    P = @get raw.producers.number
    N = @get raw.nutrients.number
    expand!(raw, to_size(bp.h, (P, N)))
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    h::@GraphData Adjacency{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Adjacency(h, nt = Nutrients._Nodes) = new(@tographdata(h, Adjacency{Float64}), nt)
end
F.implied_blueprint_for(bp::Adjacency, ::Nutrients._Nodes) =
    Nutrients.Nodes(refspace_inner(bp.h))
@blueprint Adjacency "[producer => [nutrient => half-saturation]] map"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.h)
function F.late_check(raw, bp::Adjacency)
    (; h) = bp
    p_index = @ref raw.producers.sparse_index
    n_index = @ref raw.nutrients.index
    @check_list_refs h "producer trophic" (p_index, n_index) dense
end

function F.expand!(raw, bp::Adjacency)
    p_index = @ref raw.producers.dense_index
    n_index = @ref raw.nutrients.index
    h = to_dense_matrix(bp.h, p_index, n_index)
    expand!(raw, h)
end

end

# ==========================================================================================
@component begin
    HalfSaturation{Internal}
    requires(Foodweb, Nutrients.Nodes)
    blueprints(HalfSaturation_)
end
export HalfSaturation

function (::_HalfSaturation)(h)
    h = @tographdata h {Scalar, Matrix, Adjacency}{Float64}
    if h isa Real
        HalfSaturation.Flat(h)
    elseif h isa AbstractMatrix
        HalfSaturation.Raw(h)
    else
        HalfSaturation.Adjacency(h)
    end
end

@expose_data edges begin
    property(nutrients.half_saturation)
    depends(HalfSaturation)
    row_index(raw -> @ref raw.producers.dense_index)
    col_index(raw -> @ref raw.nutrients.index)
    ref(raw -> raw._scratch[:nutrients_half_saturation])
    get(HalfSaturations{Float64}, "producer-to-nutrient link")
    write!((raw, rhs::Real, i, j) -> HalfSaturation_.check(rhs, (i, j)))
end

function F.shortline(io::IO, model::Model, ::_HalfSaturation)
    print(io, "Nutrients half-saturation: ")
    showrange(io, model.nutrients._half_saturation)
end

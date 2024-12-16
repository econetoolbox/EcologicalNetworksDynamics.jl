# Set or generate half saturation densities for every consumer in the model.

# Mostly duplicated from maximum consumption.

# (reassure JuliaLS)
(false) && (local HalfSaturationDensity, _HalfSaturationDensity)

# ==========================================================================================
# Blueprints.

module HalfSaturationDensity_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, Foodweb, _Foodweb

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    B0::SparseVector{Float64}
    species::Brought(Species)
    Raw(B0::SparseVector{Float64}, sp = _Species) = new(B0, sp)
    Raw(B0, sp = _Species) = new(@tographdata(B0, SparseVector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.B0))
@blueprint Raw "half-saturation density values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.B0)
check(B0, ref = nothing) = check_value(>=(0), B0, ref, :B0, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; B0) = bp
    cons = @ref raw.consumers.mask
    @check_template B0 cons :consumers
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.B0)
function expand!(raw, B0)
    raw._scratch[:half_saturation_density] = collect(B0) # Legacy storage is dense.
    # Keep a true sparse version in the cache.
    raw._cache[:half_saturation_density] = B0
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    B0::Float64
end
@blueprint Flat "uniform half-saturation density" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.B0)
F.expand!(raw, bp::Flat) = expand!(raw, to_template(bp.B0, @ref raw.consumers.mask))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    B0::@GraphData Map{Float64}
    Map(B0) = new(@tographdata(B0, Map{Float64}))
end
@blueprint Map "[species => half-saturation density] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.B0)
function F.late_check(raw, bp::Map)
    (; B0) = bp
    index = @ref raw.species.index
    cons = @ref raw.consumers.mask
    @check_list_refs B0 :consumer index template(cons)
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    B0 = to_sparse_vector(bp.B0, index)
    expand!(raw, B0)
end

end

# ==========================================================================================
@component HalfSaturationDensity{Internal} requires(Foodweb) blueprints(
    HalfSaturationDensity_,
)
export HalfSaturationDensity

function (::_HalfSaturationDensity)(B0)

    B0 = @tographdata B0 {Scalar, SparseVector, Map}{Float64}

    if B0 isa Real
        HalfSaturationDensity.Flat(B0)
    elseif B0 isa AbstractVector
        HalfSaturationDensity.Raw(B0)
    else
        HalfSaturationDensity.Map(B0)
    end

end

@expose_data nodes begin
    property(half_saturation_density)
    depends(HalfSaturationDensity)
    @species_index
    ref_cached(_ -> nothing) # Cache filled on component expansion.
    get(HalfSaturationDensities{Float64}, sparse, "consumer")
    template(raw -> @ref raw.consumers.mask)
    write!((raw, rhs::Real, i) -> begin
        HalfSaturationDensity_.check(rhs, i)
        rhs = Float64(rhs)
        raw._scratch[:half_saturation_density][i] = rhs
        rhs
    end)
end

F.shortline(io::IO, model::Model, ::_HalfSaturationDensity) = print(
    io,
    "Half-saturation density: [$(join_elided(model._half_saturation_density, ", "))]",
)

# Set or generate maximum consumption rates for every consumer in the model.

# Mostly duplicated from CarryingCapacity.

# (reassure JuliaLS)
(false) && (local MaximumConsumption, _MaximumConsumption)

# ==========================================================================================
# Blueprints.

module MaximumConsumption_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, Foodweb, _Foodweb, BodyMass, MetabolicClass

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    y::SparseVector{Float64}
    species::Brought(Species)
    Raw(y::SparseVector{Float64}, sp = _Species) = new(y, sp)
    Raw(y, sp = _Species) = new(@tographdata(y, SparseVector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.y))
@blueprint Raw "maximum consumption values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.y)
check(y, ref = nothing) = check_value(>=(0), y, ref, :y, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; y) = bp
    cons = @ref raw.consumers.mask
    @check_template y cons :consumers
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.y)
function expand!(raw, y)
    raw.biorates.y = collect(y) # Legacy storage is dense.
    # Keep a true sparse version in the cache.
    raw._cache[:maximum_consumption] = y
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    y::Float64
end
@blueprint Flat "uniform maximum consumption rate" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.y)
F.expand!(raw, bp::Flat) = expand!(raw, to_template(bp.y, @ref raw.consumers.mask))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    y::@GraphData Map{Float64}
    Map(y) = new(@tographdata(y, Map{Float64}))
end
@blueprint Map "[species => maximum consumption] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.y)
function F.late_check(raw, bp::Map)
    (; y) = bp
    index = @ref raw.species.index
    cons = @ref raw.consumers.mask
    @check_list_refs y :consumer index template(cons)
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    y = to_sparse_vector(bp.y, index)
    expand!(raw, y)
end

#-------------------------------------------------------------------------------------------
miele2019_allometry_rates() =
    Allometry(; ectotherm = (a = 4, b = 0), invertebrate = (a = 8, b = 0))

# TODO: since only consumers are involved,
# does it make sense to receive and process a full allometric dict here?

mutable struct Allometric <: Blueprint
    allometry::Allometry
    Allometric(; kwargs...) = new(parse_allometry_arguments(kwargs))
    Allometric(allometry::Allometry) = new(allometry)
    # Default values.
    function Allometric(default::Symbol)
        @check_symbol default (:Miele2019,)
        @expand_symbol default (:Miele2019 => new(miele2019_allometry_rates()))
    end
end
@blueprint Allometric "allometric rates" depends(BodyMass, MetabolicClass)
export Allometric

function F.early_check(bp::Allometric)
    (; allometry) = bp
    check_template(allometry, miele2019_allometry_rates(), "maximum consumption rates")
end

function F.expand!(raw, bp::Allometric)
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    cons = @ref raw.consumers.mask
    y = sparse_nodes_allometry(bp.allometry, cons, M, mc)
    expand!(raw, y)
end

end

# ==========================================================================================
@component MaximumConsumption{Internal} requires(Foodweb) blueprints(MaximumConsumption_)
export MaximumConsumption

function (::_MaximumConsumption)(y)

    y = @tographdata y {Symbol, Scalar, SparseVector, Map}{Float64}
    @check_if_symbol y (:Miele2019,)

    if y == :Miele2019
        MaximumConsumption.Allometric(y)
    elseif y isa Real
        MaximumConsumption.Flat(y)
    elseif y isa AbstractVector
        MaximumConsumption.Raw(y)
    else
        MaximumConsumption.Map(y)
    end

end

@expose_data nodes begin
    property(maximum_consumption, y)
    depends(MaximumConsumption)
    @species_index
    ref_cached(_ -> nothing) # Cache filled on component expansion.
    get(MaximumConsumptionRates{Float64}, sparse, "consumer")
    template(raw -> @ref raw.consumers.mask)
    write!((raw, rhs::Real, i) -> begin
        MaximumConsumption_.check(rhs, i)
        rhs = Float64(rhs)
        raw.biorates.y[i] = rhs
        rhs
    end)
end

F.shortline(io::IO, model::Model, ::_MaximumConsumption) =
    print(io, "Maximum consumption: [$(join_elided(model._maximum_consumption, ", "))]")

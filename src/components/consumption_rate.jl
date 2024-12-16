# Set or generate consumption rates for every consumer in the model.

# Mostly duplicated from half saturation density.

# (reassure JuliaLS)
(false) && (local ConsumptionRate, _ConsumptionRate)

# ==========================================================================================
# Blueprints.

module ConsumptionRate_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, Foodweb, _Foodweb

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    alpha::SparseVector{Float64}
    species::Brought(Species)
    Raw(alpha::SparseVector{Float64}, sp = _Species) = new(alpha, sp)
    Raw(alpha, sp = _Species) = new(@tographdata(alpha, SparseVector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.alpha))
@blueprint Raw "consumption rates"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.alpha)
check(alpha, ref = nothing) = check_value(>=(0), alpha, ref, :alpha, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; alpha) = bp
    cons = @ref raw.consumers.mask
    @check_template alpha cons :consumers
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.alpha)
function expand!(raw, alpha)
    raw._scratch[:consumption_rate] = collect(alpha) # Legacy storage is dense.
    # Keep a true sparse version in the cache.
    raw._cache[:consumption_rate] = alpha
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    alpha::Float64
end
@blueprint Flat "uniform consumption rate" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.alpha)
F.expand!(raw, bp::Flat) = expand!(raw, to_template(bp.alpha, @ref raw.consumers.mask))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    alpha::@GraphData Map{Float64}
    Map(alpha) = new(@tographdata(alpha, Map{Float64}))
end
@blueprint Map "[species => consumption rate] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.alpha)
function F.late_check(raw, bp::Map)
    (; alpha) = bp
    index = @ref raw.species.index
    cons = @ref raw.consumers.mask
    @check_list_refs alpha :consumer index template(cons)
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    alpha = to_sparse_vector(bp.alpha, index)
    expand!(raw, alpha)
end

end

# ==========================================================================================
@component ConsumptionRate{Internal} requires(Foodweb) blueprints(ConsumptionRate_)
export ConsumptionRate

function (::_ConsumptionRate)(alpha)

    alpha = @tographdata alpha {Scalar, SparseVector, Map}{Float64}

    if alpha isa Real
        ConsumptionRate.Flat(alpha)
    elseif alpha isa AbstractVector
        ConsumptionRate.Raw(alpha)
    else
        ConsumptionRate.Map(alpha)
    end

end

@expose_data nodes begin
    property(consumption_rate, alpha)
    depends(ConsumptionRate)
    @species_index
    ref_cached(_ -> nothing) # Cache filled on component expansion.
    get(ConsumptionRates{Float64}, sparse, "consumer")
    template(raw -> @ref raw.consumers.mask)
    write!((raw, rhs::Real, i) -> begin
        ConsumptionRate_.check(rhs, i)
        rhs = Float64(rhs)
        raw._scratch[:consumption_rate][i] = rhs
        rhs
    end)
end

F.shortline(io::IO, model::Model, ::_ConsumptionRate) =
    print(io, "Consumption rate: [$(join_elided(model._consumption_rate, ", "))]")

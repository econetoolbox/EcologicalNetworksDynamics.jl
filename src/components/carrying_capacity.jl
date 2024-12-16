# Set or generate carrying capacity for every producer in the model.

# Mostly duplicated from GrowthRate.

# (reassure JuliaLS)
(false) && (local CarryingCapacity, _CarryingCapacity)

# ==========================================================================================
# Blueprints.

module CarryingCapacity_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, Foodweb, _Foodweb, BodyMass, MetabolicClass, _Temperature

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    K::SparseVector{Float64}
    species::Brought(Species)
    Raw(K::SparseVector{Float64}, sp = _Species) = new(K, sp)
    Raw(K, sp = _Species) = new(@tographdata(K, SparseVector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.K))
@blueprint Raw "carrying capacity values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.K)
check(K, ref = nothing) = check_value(>=(0), K, ref, :K, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; K) = bp
    prods = @ref raw.producers.mask
    @check_template K prods :producers
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.K)
function expand!(raw, K)
    # The legacy format is a dense vector with 'nothing' values.
    res = Union{Nothing,Float64}[nothing for i in 1:length(K)]
    for (i, k) in zip(findnz(K)...)
        res[i] = k
    end
    # Store in scratch space until we're sure to bring in the "LogisticGrowth" component.
    raw._scratch[:carrying_capacity] = res
    # Keep a true sparse version in the cache.
    raw._cache[:carrying_capacity] = K
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    K::Float64
end
@blueprint Flat "uniform carrying capacity" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.K)
F.expand!(raw, bp::Flat) = expand!(raw, to_template(bp.K, @ref raw.producers.mask))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    K::@GraphData Map{Float64}
    Map(K) = new(@tographdata(K, Map{Float64}))
end
@blueprint Map "[species => carrying capacity] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.K)
function F.late_check(raw, bp::Map)
    (; K) = bp
    index = @ref raw.species.index
    prods = @ref raw.producers.mask
    @check_list_refs K :producer index template(prods)
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    K = to_sparse_vector(bp.K, index)
    expand!(raw, K)
end

#-------------------------------------------------------------------------------------------
binzer2016_allometry_rates() =
    (E_a = 0.71, allometry = Allometry(; producer = (a = 3, b = 0.28)))

# TODO: since only producers are involved,
# does it make sense to receive and process a full allometric dict here?

mutable struct Temperature <: Blueprint
    E_a::Float64
    allometry::Allometry
    Temperature(E_a; kwargs...) = new(E_a, parse_allometry_arguments(kwargs))
    Temperature(E_a, allometry::Allometry) = new(E_a, allometry)
    function Temperature(default::Symbol)
        @check_symbol default (:Binzer2016,)
        @expand_symbol default (:Binzer2016 => new(binzer2016_allometry_rates()...))
    end
end
@blueprint Temperature "allometric rates and activation energy" depends(
    _Temperature,
    BodyMass,
    MetabolicClass,
)
export Temperature

function F.early_check(bp::Temperature)
    (; allometry) = bp
    check_template(
        allometry,
        binzer2016_allometry_rates()[2],
        "carrying capacity (from temperature)",
    )
end

function F.expand!(raw, bp::Temperature)
    (; E_a) = bp
    T = @get raw.T
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    prods = @ref raw.producers.mask
    K = sparse_nodes_allometry(bp.allometry, prods, M, mc; E_a, T)
    expand!(raw, K)
end

end

# ==========================================================================================
@component CarryingCapacity{Internal} requires(Foodweb) blueprints(CarryingCapacity_)
export CarryingCapacity

function (::_CarryingCapacity)(K)

    K = @tographdata K {Symbol, Scalar, SparseVector, Map}{Float64}
    @check_if_symbol K (:Binzer2016,)

    if K == :Binzer2016
        CarryingCapacity.Temperature(K)
    elseif K isa Real
        CarryingCapacity.Flat(K)
    elseif K isa AbstractVector
        CarryingCapacity.Raw(K)
    else
        CarryingCapacity.Map(K)
    end

end

@expose_data nodes begin
    property(carrying_capacity, K)
    depends(CarryingCapacity)
    @species_index
    ref_cached(_ -> nothing) # Cache filled on component expansion.
    get(CarryingCapacities{Float64}, sparse, "producer")
    template(raw -> @ref raw.producers.mask)
    write!((raw, rhs::Real, i) -> begin
        CarryingCapacity_.check(rhs, i)
        rhs = Float64(rhs)
        raw._scratch[:carrying_capacity][i] = rhs
        rhs
    end)
end

F.shortline(io::IO, model::Model, ::_CarryingCapacity) =
    print(io, "Carrying capacity: [$(join_elided(model._carrying_capacity, ", "))]")

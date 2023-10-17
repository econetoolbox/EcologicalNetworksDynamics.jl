# Set or generate intra-specific interference for every consumer in the model.

# Mostly duplicated from half saturation density.

# (reassure JuliaLS)
(false) && (local IntraspecificInterference, _IntraspecificInterference)

# ==========================================================================================
# Blueprints.

module IntraspecificInterference_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, Foodweb, _Foodweb

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    c::SparseVector{Float64}
    species::Brought(Species)
    Raw(c::SparseVector{Float64}, sp = _Species) = new(c, sp)
    Raw(c, sp = _Species) = new(@tographdata(c, SparseVector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.c))
@blueprint Raw "intra-specific interference values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.c)
check(c, ref = nothing) = check_value(>=(0), c, ref, :c, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; c) = bp
    cons = @ref raw.consumers.mask
    @check_template c cons :consumers
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.c)
function expand!(raw, c)
    raw._scratch[:intraspecific_interference] = collect(c) # Legacy storage is dense.
    # Keep a true sparse version in the cache.
    raw._cache[:intraspecific_interference] = c
end

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    c::Float64
end
@blueprint Flat "uniform intra-specific interference" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.c)
F.expand!(raw, bp::Flat) = expand!(raw, to_template(bp.c, @ref raw.consumers.mask))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    c::@GraphData Map{Float64}
    Map(c) = new(@tographdata(c, Map{Float64}))
end
@blueprint Map "[species => intra-specific interference] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.c)
function F.late_check(raw, bp::Map)
    (; c) = bp
    index = @ref raw.species.index
    cons = @ref raw.consumers.mask
    @check_list_refs c :consumer index template(cons)
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    c = to_sparse_vector(bp.c, index)
    expand!(raw, c)
end

end

# ==========================================================================================
@component IntraspecificInterference{Internal} requires(Foodweb) blueprints(
    IntraspecificInterference_,
)
export IntraspecificInterference

function (::_IntraspecificInterference)(c)

    c = @tographdata c {Scalar, SparseVector, Map}{Float64}

    if c isa Real
        IntraspecificInterference.Flat(c)
    elseif c isa AbstractVector
        IntraspecificInterference.Raw(c)
    else
        IntraspecificInterference.Map(c)
    end

end

@expose_data nodes begin
    property(intraspecific_interference)
    depends(IntraspecificInterference)
    @species_index
    ref_cached(_ -> nothing) # Cache filled on component expansion.
    get(IntraspecificInterferences{Float64}, sparse, "consumer")
    template(raw -> @ref raw.consumers.mask)
    write!((raw, rhs::Real, i) -> begin
        IntraspecificInterference_.check(rhs, i)
        rhs = Float64(rhs)
        raw._scratch[:intraspecific_interference][i] = rhs
        rhs
    end)
end

F.shortline(io::IO, model::Model, ::_IntraspecificInterference) = print(
    io,
    "Intra-specific interference: \
     [$(join_elided(model._intraspecific_interference, ", "))]",
)

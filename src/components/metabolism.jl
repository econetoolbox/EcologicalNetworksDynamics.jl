# Set or generate metabolism rates for every species in the model.

# Mostly duplicated from Mortality.

# (reassure JuliaLS)
(false) && (local Metabolism, _Metabolism)

# ==========================================================================================
# Blueprints.

module Metabolism_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, BodyMass, MetabolicClass, _Temperature

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    x::Vector{Float64}
    species::Brought(Species)
    Raw(x::Vector{Float64}, sp = _Species) = new(x, sp)
    Raw(x, sp = _Species) = new(@tographdata(x, Vector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.x))
@blueprint Raw "metabolism values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.x)
check(x, ref = nothing) = check_value(>=(0), x, ref, :x, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; x) = bp
    S = @get raw.species.number
    @check_size x S
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.x)
expand!(raw, x) = raw.biorates.x = x

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    x::Float64
end
@blueprint Flat "uniform metabolism" depends(Species)
export Flat

F.early_check(bp::Flat) = check(bp.x)
F.expand!(raw, bp::Flat) = expand!(raw, to_size(bp.x, @get raw.species.number))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    x::@GraphData Map{Float64}
    species::Brought(Species)
    Map(x, sp = _Species) = new(@tographdata(x, Map{Float64}), sp)
end
F.implied_blueprint_for(bp::Map, ::_Species) = Species(refspace(bp.x))
@blueprint Map "[species => metabolism] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.x)
function F.late_check(raw, bp::Map)
    (; x) = bp
    index = @ref raw.species.index
    @check_list_refs x :species index dense
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    r = to_dense_vector(bp.x, index)
    expand!(raw, r)
end

#-------------------------------------------------------------------------------------------
miele2019_allometry_rates() = Allometry(;
    producer = (a = 0, b = 0),
    invertebrate = (a = 0.314, b = -1 / 4),
    ectotherm = (a = 0.88, b = -1 / 4),
)

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
    check_template(allometry, miele2019_allometry_rates(), "metabolism rates")
end

function F.expand!(raw, bp::Allometric)
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    x = dense_nodes_allometry(bp.allometry, M, mc)
    expand!(raw, x)
end

#-------------------------------------------------------------------------------------------
binzer2016_allometry_rates() = (
    E_a = -0.69,
    allometry = Allometry(;
        producer = (a = 0, b = -0.31), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(-16.54), b = -0.31),
        ectotherm = (a = exp(-16.54), b = -0.31),
    ),
)

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
        "metabolism (from temperature)",
    )
end

function F.expand!(raw, bp::Temperature)
    (; E_a) = bp
    T = @get raw.T
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    x = dense_nodes_allometry(bp.allometry, M, mc; E_a, T)
    expand!(raw, x)
end

end

# ==========================================================================================
@component Metabolism{Internal} requires(Species) blueprints(Metabolism_)
export Metabolism

function (::_Metabolism)(x)

    x = @tographdata x {Symbol, Scalar, Vector, Map}{Float64}
    @check_if_symbol x (:Miele2019, :Binzer2016)

    if x == :Miele2019
        Metabolism.Allometric(x)
    elseif x == :Binzer2016
        Metabolism.Temperature(x)
    elseif x isa Real
        Metabolism.Flat(x)
    elseif x isa Vector
        Metabolism.Raw(x)
    else
        Metabolism.Map(x)
    end

end

@expose_data nodes begin
    property(metabolism, x)
    depends(Metabolism)
    @species_index
    ref(raw -> raw.biorates.x)
    get(MetabolismRates{Float64}, "species")
    write!((raw, rhs::Real, i) -> Metabolism_.check(rhs, i))
end

F.shortline(io::IO, model::Model, ::_Metabolism) =
    print(io, "Metabolism: [$(join_elided(model._metabolism, ", "))]")

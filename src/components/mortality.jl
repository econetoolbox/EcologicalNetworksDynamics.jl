# Set or generate mortality rates for every species in the model.

# Mostly duplicated from Growth rates.

# (reassure JuliaLS)
(false) && (local Mortality, _Mortality)

# ==========================================================================================
# Blueprints.

module Mortality_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Species, _Species, BodyMass, MetabolicClass

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    d::Vector{Float64}
    species::Brought(Species)
    Raw(d::Vector{Float64}, sp = _Species) = new(d, sp)
    Raw(d, sp = _Species) = new(@tographdata(d, Vector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.d))
@blueprint Raw "mortality values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.d)
check(d, ref = nothing) = check_value(>=(0), d, ref, :d, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; d) = bp
    S = @get raw.species.number
    @check_size d S
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.d)
expand!(raw, d) = raw.biorates.d = d

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    d::Float64
end
@blueprint Flat "uniform mortality" depends(Species)
export Flat

F.early_check(bp::Flat) = check(bp.d)
F.expand!(raw, bp::Flat) = expand!(raw, to_size(bp.d, @get raw.species.number))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    d::@GraphData Map{Float64}
    species::Brought(Species)
    Map(d, sp = _Species) = new(@tographdata(d, Map{Float64}), sp)
end
F.implied_blueprint_for(bp::Map, ::_Species) = Species(refspace(bp.d))
@blueprint Map "[species => mortality] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.d)
function F.late_check(raw, bp::Map)
    (; d) = bp
    index = @ref raw.species.index
    @check_list_refs d :species index dense
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    r = to_dense_vector(bp.d, index)
    expand!(raw, r)
end

#-------------------------------------------------------------------------------------------
miele2019_allometry_rates() = Allometry(;
    producer = (a = 0.0138, b = -1 / 4),
    invertebrate = (a = 0.0314, b = -1 / 4),
    ectotherm = (a = 0.0314, b = -1 / 4),
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
    check_template(allometry, miele2019_allometry_rates(), "mortality rates")
end

function F.expand!(raw, bp::Allometric)
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    d = dense_nodes_allometry(bp.allometry, M, mc)
    expand!(raw, d)
end

#-------------------------------------------------------------------------------------------
end

# ==========================================================================================
@component Mortality{Internal} requires(Species) blueprints(Mortality_)
export Mortality

function (::_Mortality)(d)

    d = @tographdata d {Symbol, Scalar, Vector, Map}{Float64}
    @check_if_symbol d (:Miele2019,)

    if d == :Miele2019
        Mortality.Allometric(d)
    elseif d isa Real
        Mortality.Flat(d)
    elseif d isa Vector
        Mortality.Raw(d)
    else
        Mortality.Map(d)
    end

end

@expose_data nodes begin
    property(mortality, d)
    depends(Mortality)
    @species_index
    ref(raw -> raw.biorates.d)
    get(MortalityRates{Float64}, "species")
    write!((raw, rhs::Real, i) -> Mortality_.check(rhs, i))
end

F.shortline(io::IO, model::Model, ::_Mortality) =
    print(io, "Mortality: [$(join_elided(model._mortality, ", "))]")

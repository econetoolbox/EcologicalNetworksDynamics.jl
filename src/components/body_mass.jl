# Set or generate body masses for every species in the model.

# (reassure JuliaLS)
(false) && (local BodyMass, _BodyMass)

# ==========================================================================================
# Blueprints.

module BodyMass_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EcologicalNetworksDynamics: _Species, Species, _Foodweb, Foodweb

#-------------------------------------------------------------------------------------------
# From raw values.

mutable struct Raw <: Blueprint
    M::Vector{Float64}
    species::Brought(Species)
    Raw(M, sp = _Species) = new(@tographdata(M, Vector{Float64}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.M))
@blueprint Raw "masses values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.M)
check(M, ref = nothing) = check_value(>=(0), M, ref, :M, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; M) = bp
    S = n_nodes(raw, :species)
    @check_size M S
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.M)
expand!(raw, M) = add_field!(raw.classes[:species], :body_mass, deepcopy(M))

#-------------------------------------------------------------------------------------------
# From a scalar broadcasted to all species.

mutable struct Flat <: Blueprint
    M::Float64
end
@blueprint Flat "uniform mass value" depends(Species)
export Flat

F.early_check(bp::Flat) = check(bp.M)
F.expand!(raw, bp::Flat) = expand!(raw, to_size(bp.M, @get raw.S))

#-------------------------------------------------------------------------------------------
# From a species-indexed map.

mutable struct Map <: Blueprint
    M::@GraphData Map{Float64}
    species::Brought(Species)
    Map(M, sp = _Species) = new(@tographdata(M, Map{Float64}), sp)
end
F.implied_blueprint_for(bp::Map, ::_Species) = Species(refspace(bp.M))
@blueprint Map "[species => mass] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.M)
function F.late_check(raw, bp::Map)
    (; M) = bp
    index = @ref raw.species.index
    @check_list_refs M :species index dense
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    M = to_dense_vector(bp.M, index)
    expand!(raw, M)
end

#-------------------------------------------------------------------------------------------
# From trophic levels with a Z-value.

mutable struct Z <: Blueprint
    Z::Float64
end
@blueprint Z "trophic levels" depends(Foodweb)
export Z

function F.late_check(_, bp::Z)
    (; Z) = bp
    Z >= 0 || checkfails("Cannot calculate body masses from trophic levels \
                          with a negative value of Z: $Z.")
end

function F.expand!(raw, bp::Z)
    A = @ref raw.A
    M = Internals.compute_mass(A, bp.Z)
    expand!(raw, M)
end

end

# ==========================================================================================
# Component and generic constructors.

@component BodyMass{Internal} requires(Species) blueprints(BodyMass_)
export BodyMass

(::_BodyMass)(M::Real) = BodyMass.Flat(M)

function (::_BodyMass)(; Z = nothing)
    isnothing(Z) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
    BodyMass.Z(Z)
end

function (::_BodyMass)(M)
    M = @tographdata M {Vector, Map}{Float64}
    if M isa Vector
        BodyMass.Raw(M)
    else
        BodyMass.Map(M)
    end
end

# Basic query.
@expose_data nodes begin
    property(body_mass, M)
    depends(BodyMass)
    @species_index
    # HERE: should @ref expose the actual entry to lib devs?
    ref(raw -> Networks.read(collect, raw.classes[:species].data[:body_mass]))
    get(BodyMasses{Float64}, "species")
    write!((raw, rhs::Real, i) -> BodyMass_.check(rhs, i))
end

# Display.
F.shortline(io::IO, model::Model, ::_BodyMass) =
    print(io, "BodyMass: [$(join_elided(model.body_mass, ", "))]")

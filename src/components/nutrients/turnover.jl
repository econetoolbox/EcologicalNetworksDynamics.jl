# Set or generate turnover rates for every nutrients in the model.

# Mostly duplicated from BodyMass.

# (reassure JuliaLS)
(false) && (local Turnover, _Turnover)

# ==========================================================================================
module Turnover_
include("../blueprint_modules.jl")
include("../blueprint_modules_identifiers.jl")
import .EN: Nutrients

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    t::Vector{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Raw(t, nt = Nutrients._Nodes) = new(@tographdata(t, Vector{Float64}), nt)
end
F.implied_blueprint_for(bp::Raw, ::Nutrients._Nodes) = Nutrients.Nodes(length(bp.t))
@blueprint Raw "turnover values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.t)
check(t, ref = nothing) = check_value(>=(0), t, ref, :t, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; t) = bp
    N = @get raw.nutrients.number
    @check_size t N
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.t)
expand!(raw, t) = raw._scratch[:nutrients_turnover] = t

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    t::Float64
end
@blueprint Flat "uniform turnover value" depends(Nutrients.Nodes)
export Flat

F.early_check(bp::Flat) = check(bp.t)
F.expand!(raw, bp::Flat) = expand!(raw, to_size(bp.t, @get raw.nutrients.number))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    t::@GraphData Map{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Map(t, nt = Nutrients._Nodes) = new(@tographdata(t, Map{Float64}), nt)
end
F.implied_blueprint_for(bp::Map, ::Nutrients._Nodes) = Nutrients.Nodes(refspace(bp.t))
@blueprint Map "[nutrient => turnover] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.t)
function F.late_check(raw, bp::Map)
    (; t) = bp
    index = @ref raw.nutrients.index
    @check_list_refs t :nutrient index dense
end

function F.expand!(raw, bp::Map)
    index = @ref raw.nutrients.index
    t = to_dense_vector(bp.t, index)
    expand!(raw, t)
end

end

# ==========================================================================================
@component Turnover{Internal} requires(Nutrients.Nodes) blueprints(Turnover_)
export Turnover

function (::_Turnover)(t)
    t = @tographdata t {Scalar, Vector, Map}{Float64}
    if t isa Real
        Turnover.Flat(t)
    elseif t isa AbstractVector
        Turnover.Raw(t)
    else
        Turnover.Map(t)
    end
end

@expose_data nodes begin
    property(nutrients.turnover)
    depends(Turnover)
    @nutrients_index
    ref(raw -> raw._scratch[:nutrients_turnover])
    get(TurnoverRates{Float64}, "nutrient")
    write!((raw, rhs::Real, i) -> Turnover_.check(rhs, i))
end

F.shortline(io::IO, model::Model, ::_Turnover) =
    print(io, "Nutrients turnover: [$(join_elided(model.nutrients._turnover, ", "))]")

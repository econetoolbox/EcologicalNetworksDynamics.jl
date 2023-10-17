# Set or generate supply rates for every nutrients in the model.

# Mostly duplicated from Turnover.

# (reassure JuliaLS)
(false) && (local Supply, _Supply)

# ==========================================================================================
module Supply_
include("../blueprint_modules.jl")
include("../blueprint_modules_identifiers.jl")
import .EN: Nutrients

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    s::Vector{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Raw(s, nt = Nutrients._Nodes) = new(@tographdata(s, Vector{Float64}), nt)
end
F.implied_blueprint_for(bp::Raw, ::Nutrients._Nodes) = Nutrients.Nodes(length(bp.s))
@blueprint Raw "supply values"
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.s)
check(s, ref = nothing) = check_value(>=(0), s, ref, :s, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; s) = bp
    N = @get raw.nutrients.number
    @check_size s N
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.s)
expand!(raw, s) = raw._scratch[:nutrients_supply] = s

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    s::Float64
end
@blueprint Flat "uniform supply value" depends(Nutrients.Nodes)
export Flat

F.early_check(bp::Flat) = check(bp.s)
F.expand!(raw, bp::Flat) = expand!(raw, to_size(bp.s, @get raw.nutrients.number))

#-------------------------------------------------------------------------------------------
mutable struct Map <: Blueprint
    s::@GraphData Map{Float64}
    nutrients::Brought(Nutrients.Nodes)
    Map(s, nt = Nutrients._Nodes) = new(@tographdata(s, Map{Float64}), nt)
end
F.implied_blueprint_for(bp::Map, ::Nutrients._Nodes) = Nutrients.Nodes(refspace(bp.s))
@blueprint Map "[nutrient => supply] map"
export Map

F.early_check(bp::Map) = check_nodes(check, bp.s)
function F.late_check(raw, bp::Map)
    (; s) = bp
    index = @ref raw.nutrients.index
    @check_list_refs s :nutrient index dense
end

function F.expand!(raw, bp::Map)
    index = @ref raw.nutrients.index
    s = to_dense_vector(bp.s, index)
    expand!(raw, s)
end

end

# ==========================================================================================
@component Supply{Internal} requires(Nutrients.Nodes) blueprints(Supply_)
export Supply

function (::_Supply)(s)
    s = @tographdata s {Scalar, Vector, Map}{Float64}
    if s isa Real
        Supply.Flat(s)
    elseif s isa AbstractVector
        Supply.Raw(s)
    else
        Supply.Map(s)
    end
end

@expose_data nodes begin
    property(nutrients.supply)
    depends(Supply)
    @nutrients_index
    ref(raw -> raw._scratch[:nutrients_supply])
    get(SupplyRates{Float64}, "nutrient")
    write!((raw, rhs::Real, i) -> Supply_.check(rhs, i))
end

F.shortline(io::IO, model::Model, ::_Supply) =
    print(io, "Nutrients supply: [$(join_elided(model.nutrients._supply, ", "))]")

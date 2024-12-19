# Nutrients nodes compartments, akin to species nodes.
# Call it 'Nodes' because the module is already named 'Nutrients'.

(false) && (local Nodes, _Nodes)

# ==========================================================================================
module Nodes_
include("../blueprint_modules.jl")
include("../blueprint_modules_identifiers.jl")
import .EN: Foodweb

#-------------------------------------------------------------------------------------------
# From a given set of names.

mutable struct Names <: Blueprint
    names::Vector{Symbol}

    # Convert anything to symbols.
    Names(names) = new(@tographdata(names, Vector{Symbol}))
    Names(names...) = new(Symbol.(collect(names)))

    # From an index (useful when implied).
    function Names(index::AbstractDict{Symbol,Int})
        check_index(index)
        new(to_dense_refs(index))
    end

    # Don't own data if useful to user.
    Names(names::Vector{Symbol}) = new(names)
end
@blueprint Names "raw nutrients names"
export Names

# Forbid duplicates (triangular check).
function F.early_check(bp::Names)
    (; names) = bp
    for (i, a) in enumerate(names)
        for j in (i+1):length(names)
            b = names[j]
            a == b && checkfails("Nutrients $i and $j are both named $(repr(a)).")
        end
    end
end

F.expand!(raw, bp::Names) = expand!(raw, bp.names)
function expand!(raw, names)
    # Store in the scratch, and only alias to model.producer_growth
    # if the corresponding component is loaded.
    raw._scratch[:nutrients_names] = names
    raw._scratch[:nutrients_index] = OrderedDict(n => i for (i, n) in enumerate(names))

    # Update topology.
    top = raw._topology
    add_nodes!(top, names, :nutrients)
end

#-------------------------------------------------------------------------------------------
# From a plain number and generate dummy names.

mutable struct Number <: Blueprint
    n::UInt
end
@blueprint Number "number of nutrients"
export Number

F.expand!(raw, bp::Number) = expand!(raw, default_names(bp.n))
default_names(n) = [Symbol(:n, i) for i in 1:n]

#-------------------------------------------------------------------------------------------
# From a foodweb.
mutable struct PerProducer <: Blueprint
    n::UInt # Number of nutrients per producer.
    PerProducer(n = 1) = new(n)
end
@blueprint PerProducer "producers in the foodweb" depends(Foodweb)
export PerProducer

function F.expand!(raw, bp::PerProducer)
    n = bp.n * @get raw.producers.number
    expand!(raw, default_names(n))
end

end

# ==========================================================================================
@component Nodes{Internal} blueprints(Nodes_)
# Don't export, to encourage disambiguated access as `Nutrients.Nodes`.

# In the presence of trophic links, all producers
# become connected to all nutrient nodes.
# TODO: maybe this should be alleviated in case feeding coefficients are zero.
# In this situation, the edges would only appear when adding
# concentration/half-saturation coefficients.
F.add_trigger!(
    [Foodweb, Nodes],
    raw -> begin
        top = raw._topology
        edges = repeat(@ref(raw.producers.mask), 1, @get(raw.nutrients.number))
        add_edges_accross_node_types!(top, :species, :nutrients, :trophic, edges)
    end,
)

(::_Nodes)(n::Integer) = Nodes.Number(n)
(::_Nodes)(names) = Nodes.Names(names)
(::_Nodes)(; per_producer = 1) = Nodes.PerProducer(per_producer)

function F.shortline(io::IO, model::Model, ::_Nodes)
    N = model.nutrients.number
    names = model.nutrients.names
    print(io, "Nutrients: $N ($(join_elided(names, ", ")))")
end

# ==========================================================================================
# Queries, similar to Species components.

@expose_data nodes begin
    property(nutrients.names)
    get(NutrientsNames{Symbol}, "nutrient")
    ref(raw -> raw._scratch[:nutrients_names])
    depends(Nodes)
end

@expose_data graph begin
    property(nutrients.number, nutrients.richness)
    get(raw -> length(@ref raw.nutrients.names))
    depends(Nodes)
end

@expose_data graph begin
    property(nutrients.index)
    ref_cached(
        raw -> OrderedDict(name => i for (i, name) in enumerate(@ref raw.nutrients.names)),
    )
    get(raw -> deepcopy(@ref raw.nutrients.index))
    depends(Nodes)
end

@expose_data graph begin
    property(nutrients.label)
    ref_cached(
        raw ->
            (i) -> begin
                names = @ref raw.nutrients.names
                n = length(names)
                if 1 <= i <= length(names)
                    names[i]
                else
                    (are, s) = n > 1 ? ("are", "s") : ("is", "")
                    argerr("Invalid index ($(i)) when there $are $n nutrient name$s.")
                end
            end,
    )
    get(raw -> @ref raw.nutrients.label)
    depends(Nodes)
end

macro nutrients_index()
    esc(:(index(raw -> @ref raw.nutrients.index)))
end

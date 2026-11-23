"Direct dense view into nodes field data."
struct NodeFieldView{s,T} <: AbstractVector{T} # s::S.NodeField
    model::Model
    view::ST.NodeView{T}
end

function field_view(s::SL.NodeField, m::Model)
    view = ST.nodes_view(ST.network(m), SL.classname(s), SL.fieldname(s))
    T = eltype(view)
    NodeFieldView{s,T}(m, view)
end

let V = NodeFieldView
    ST.restriction(v::V) = ST.class(v).restriction
    Base.size(v::V) = (v |> ST.view |> length,)
    VW.extract(v::V) = read(collect, ST.entry(v))
    ST.class(v::V) = v |> ST.view |> ST.class

    # Extract legacy sparse view.
    function VW.spextract(v::V, parent::Option{Symbol} = nothing)
        nw, cl = ST.network(v), ST.class(v)
        par, rs = if isnothing(parent)
            # Default: pick direct parent from underlying model.
            isnothing(cl.parent) && argerr("Cannot sparse-extract from a root class: \
                                            $green$(repr(cl.name))$reset.")
            cl.parent, cl.restriction
        else
            parent, ST.restriction(nw, SL.classname(v), parent)
        end
        T = eltype(v)
        n = length(ST.class(nw, par))
        read(ST.entry(v)) do data
            ST.expand(T, rs, n, data)
        end
    end
end

# ==========================================================================================
# Views into topology-related data, read-only.

"View into network class label names, read-only."
struct NodeNameView{s} <: AbstractVector{Symbol} # s::S.Class
    model::Model
    index::ST.Index # Cache an alias to underlying class index.
end
function names_view(s::SL.Class, m::Model)
    index = ST.class(ST.network(m), SL.classname(s)).index
    NodeNameView{s}(m, index)
end
let V = NodeNameView
    ST.index(v::V) = getfield(v, :index)
    Base.size(v::V) = (v |> ST.index |> length,)
    VW.extract(v::V) = copy(ST.index(v).reverse)
end

#-------------------------------------------------------------------------------------------
"View into network class restriction mask, read-only."
struct NodeMaskView{s} <: AbstractSparseVector{Bool,Int} # s::S.Subclass
    model::Model
    restriction::ST.Restriction # Cache an alias to underlying restriction.
end
function mask_view(s::SL.Subclass, m::Model)
    r = ST.restriction(ST.network(m), SL.classname(s), SL.parentname(s))
    NodeMaskView{s}(m, r)
end
let V = NodeMaskView
    ST.restriction(v::V) = getfield(v, :restriction)
    SL.parentname(v::V) = v |> selector |> SL.parentname
    function ST.parent(v::V) # Return self-class if no parent.
        p = SL.parentname(v)
        isnothing(p) ? ST.class(v) : ST.class(ST.network(v), p)
    end
    function Base.size(v::V)
        net = ST.network(v)
        p = SL.parentname(v)
        n = isnothing(p) ? ST.n_nodes(net) : length(ST.class(net, p))
        (n,)
    end
    function VW.extract(v::V)
        res = spzeros(Bool, length(v))
        for i in v |> ST.restriction |> ST.indices
            res[i] = true
        end
        res
    end
end

# ==========================================================================================
# Abstract into categories.

const NodeTopologyView{s} = Union{NodeNameView{s},NodeMaskView{s}}
const DenseNodeView{s} = Union{NodeFieldView{s},NodeNameView{s},NodeMaskView{s}}
const NodeView{s} = Union{NodeFieldView{s},NodeNameView{s},NodeMaskView{s}}

let V = NodeView
    SL.class(v::V) = v |> selector |> SL.class
    SL.classname(v::V) = v |> selector |> SL.classname
    ST.class(v::V) = ST.class(IT.model(v), selector(v))
    ST.index(v::V) = ST.class(v).index
    ST.is_root(v::V) = v |> ST.class |> ST.is_root
end

"Direct dense view into nodes field data."
struct NodeFieldView{d,T} <: AbstractVector{T} # d::D.NodeField
    model::Model
    view::N.NodeView{T}
end

function field_view(d::D.NodeField, m::Model)
    view = N.nodes_view(N.network(m), D.class(d), D.field(d))
    T = eltype(view)
    NodeFieldView{d,T}(m, view)
end

let S = NodeFieldView
    N.restriction(s::S) = N.class(s).restriction
    Base.size(s::S) = (s |> N.view |> length,)
    V.extract(s::S) = read(collect, N.entry(s))
    N.class(s::S) = s |> N.view |> N.class

    # Extract legacy sparse view.
    function V.spextract(s::S, parent::Option{Symbol} = nothing)
        nw, cl = N.network(s), N.class(s)
        par, rs = if isnothing(parent)
            # Default: pick direct parent from underlying model.
            isnothing(cl.parent) && argerr("Cannot sparse-extract from a root class: \
                                            $green$(repr(cl.name))$reset.")
            cl.parent, cl.restriction
        else
            parent, N.restriction(nw, D.class(s), parent)
        end
        T = eltype(s)
        n = length(N.class(nw, par))
        read(N.entry(s)) do data
            N.expand(T, rs, n, data)
        end
    end
end

# ==========================================================================================
# Views into topology-related data, read-only.

"View into network class label names, read-only."
struct NodeNameView{d} <: AbstractVector{Symbol} # d::D.Class
    model::Model
    index::N.Index # Cache an alias to underlying class index.
end
function names_view(d::D.Class, m::Model)
    index = N.class(N.network(m), D.class(d)).index
    NodeNameView{d}(m, index)
end
let S = NodeNameView
    N.index(s::S) = getfield(s, :index)
    Base.size(s::S) = (s |> N.index |> length,)
    V.extract(s::S) = copy(N.index(s).reverse)
end

#-------------------------------------------------------------------------------------------
"View into network class restriction mask, read-only."
struct NodeMaskView{d} <: AbstractSparseVector{Bool,Int} # d::D.Subclass
    model::Model
    restriction::N.Restriction # Cache an alias to underlying restriction.
end
function mask_view(d::D.Subclass, m::Model)
    r = N.restriction(N.network(m), D.class(d), D.parent(d))
    NodeMaskView{d}(m, r)
end
let S = NodeMaskView
    N.restriction(s::S) = getfield(s, :restriction)
    D.parent(s::S) = s |> dispatcher |> D.parent
    function N.parent(s::S) # Return self-class if no parent.
        p = D.parent(s)
        isnothing(p) ? N.class(s) : N.class(N.network(s), p)
    end
    function Base.size(s::S)
        net = N.network(s)
        p = D.parent(s)
        n = isnothing(p) ? N.n_nodes(net) : length(N.class(net, p))
        (n,)
    end
    function V.extract(s::S)
        res = spzeros(Bool, length(s))
        for i in s |> N.restriction |> N.indices
            res[i] = true
        end
        res
    end
end

# ==========================================================================================
# Abstract into categories.

const NodeTopologyView{d} = Union{NodeNameView{d},NodeMaskView{d}}
const DenseNodeView{d} = Union{NodeFieldView{d},NodeNameView{d},NodeMaskView{d}}
const NodeView{d} = Union{NodeFieldView{d},NodeNameView{d},NodeMaskView{d}}

let S = NodeView
    D.class(s::S) = D.class(dispatcher(s))
    N.class(s::S) = N.class(N.network(s), D.class(s))
    N.index(s::S) = N.class(s).index
    N.is_root(s::S) = s |> N.class |> N.is_root
end

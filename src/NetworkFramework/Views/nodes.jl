"""
Direct dense view into nodes field data.
"""
struct NodesFieldView{d,T} <: AbstractVector{T} # d::D.Class
    model::Model
    view::N.NodesView{T}
end
let S = NodesFieldView
    N.restriction(s::S) = N.class(s).restriction
    Base.size(s::S) = (s |> N.view |> length,)
    V.extract(s::S) = read(collect, N.entry(s))
end

#-------------------------------------------------------------------------------------------
"""
View into nodes data of a subclass
from the perspective of a superclass,
resulting in incomplete / sparse data view.
"""
struct SubnodesFieldView{d,T} <: AbstractSparseVector{T,Int} # d::D.Subclass
    model::Model
    view::N.NodesView{T}
end
let S = SubnodesFieldView

    D.parent(s::S) = s |> dispatcher |> D.parent

    N.restriction(s::S) = N.restriction(N.network(s), D.class(s), D.parent(s))
    N.parent_index(s::S) = N.class(N.network(s), D.parent(s)).index
    Base.size(s::S) = (N.n_nodes(N.network(s), D.parent(s)),)

    # Duty to AbstractSparseVector..?
    SparseArrays.nonzeroinds(s::S) = s |> N.restriction |> N.indices |> collect
    SparseArrays.nonzeros(s::S) = read(collect, N.entry(s))
    SparseArrays.findnz(s::S) = (SparseArrays.nonzeroinds(s), nonzeros(s))
    SparseArrays.nnz(s::S) = s |> N.restriction |> length

    function V.extract(s::S)
        T = eltype(s)
        n = length(s)
        r = N.restriction(s)
        res = spzeros(T, n)
        for i in 1:n
            if i in r
                res[i] = s[i]
            end
        end
        res
    end
end

#-------------------------------------------------------------------------------------------
# Common to all nodes field views.

const AbstractNodesFieldView{d,T} = Union{NodesFieldView{d,T},SubnodesFieldView{d,T}}
function field_view(d::D.AbstractNodeField, m::Model)
    view = N.nodes_view(N.network(m), D.class(d), D.field(d))
    View = D.viewtype(d)
    T = eltype(view)
    View{d,T}(m, view)
end
let S = AbstractNodesFieldView
    N.class(s::S) = s |> N.view |> N.class
end

# ==========================================================================================
# Views into topology-related data, read-only.

"""
View into network class label names, read-only.
"""
struct NodesNamesView{d} <: AbstractVector{Symbol} # d::D.Class
    model::Model
    index::N.Index # Cache an alias to underlying class index.
end
function names_view(d::D.Class, m::Model)
    index = N.class(N.network(m), D.class(d)).index
    NodesNamesView{d}(m, index)
end
let S = NodesNamesView
    N.index(s::S) = getfield(s, :index)
    Base.size(s::S) = (s |> N.index |> length,)
    V.extract(s::S) = copy(N.index(s).reverse)
end

#-------------------------------------------------------------------------------------------
"""
View into network class restriction mask, read-only.
"""
struct NodesMaskView{d} <: AbstractVector{Bool} # d::D.Subclass
    model::Model
    restriction::N.Restriction # Cache an alias to underlying restriction.
end
function mask_view(d::D.Subclass, m::Model)
    r = N.restriction(N.network(m), D.class(d), D.parent(d))
    NodesMaskView{d}(m, r)
end
let S = NodesMaskView
    D.parent(s::S) = s |> dispatcher |> D.parent
    N.parent(s::S) = N.class(N.network(s), D.parent(s))
    N.restriction(s::S) = getfield(s, :restriction)
    function Base.size(s::S)
        net = N.network(s)
        p = D.parent(s)
        n = isnothing(p) ? N.n_nodes(net) : length(N.class(net, p))
        (n,)
    end
    function V.extract(s::S)
        res = spzeros(Bool, length(s))
        for i in s |> restriction |> N.indices
            res[i] = true
        end
        res
    end
end

# ==========================================================================================
# Abstract into categories.

const NodeTopologyView{d} = Union{NodesNamesView{d},NodesMaskView{d}}
const DenseNodeView{d} = Union{NodesFieldView{d},NodesNamesView{d},NodesMaskView{d}}
const NodesView{d} = Union{AbstractNodesFieldView{d},NodesNamesView{d},NodesMaskView{d}}

let S = NodesView
    D.class(s::S) = D.class(dispatcher(s))
    N.class(s::S) = N.class(N.network(s), D.class(s))
    N.index(s::S) = N.class(s).index
end

"""
Types in this module provide protected-yet-ergonomic 'views' into the model data,
with the following intent:

  - Ergonomics:

      + Node-level data behave almost as dense/sparse vectors.
      + Edge-level data behave almost as dense/sparse matrices.
      + Index with class/web local integers.
      + Index with absolute labels symbols.
      + Convenience extraction under proper dense/sparse vectors/matrices.

  - Protection:

      + Only mutable if the underlying model/network allows it.
      + Enforce underlying COW pattern.
      + Avoids leaking references to underlying data.

Views mostly wrap a Networks.View along with a reference to its model.
"""
module Views

using ..Networks
using ..Display
import ..Model

const N = Networks
const V = Views
const Option{T} = Union{T,Nothing}

#-------------------------------------------------------------------------------------------
"""
Direct dense view into nodes class data.
"""
struct NodesView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
end
S = NodesView # "Self"
Base.length(v::S) = length(view(v))
Base.getindex(v::S, i) = getindex(view(v), i) # WARN: leak if entry is mutable?
Base.setindex!(v::S, x, i) = setindex!(view(v), x, i)
nodes_view(m::Model, class::Symbol, data::Symbol) =
    NodesView(m, N.nodes_view(m._value, class, data), data)
export nodes_view

#-------------------------------------------------------------------------------------------
"""
Sparse view into nodes class data,
from the perspective of a superclass.
"""
struct SparseNodesView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    parent::Option{Symbol}
end
S = SparseNodesView
parent(v::S) = getfield(v, :parent)
restriction(v::S) = N.restriction(network(v), class(v).name, parent(v))
Base.length(v::S) = n_nodes(network(v), parent(v))
nodes_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}}, data::Symbol) =
    SparseNodesView(m, N.nodes_view(m._value, class, data), data, parent)
Base.getindex(v::S, l::Symbol) = getindex(view(v), l)
Base.setindex!(v::S, x, l::Symbol) = setindex!(view(v), x, l)

function Base.getindex(v::S, i::Int)
    i = convert_sparse_index(v, i)
    read(entry(v), getindex, i)
end

function Base.setindex!(v::S, x, i::Int)
    i = convert_sparse_index(v, i)
    mutate!(entry(v), setindex!, x, i)
end

function convert_sparse_index(v::S, i::Int)
    n, s = ns(length(v))
    i in 1:n || err(v, "Cannot index with $i for a view with $n node$s.")
    r = restriction(v)
    if !(i in r)
        class = repr(V.class(v).name)
        parent = repr(V.parent(v))
        err(v, "Node $i in $parent is not an node in $class.")
    end
    N.tolocal(i, r)
end

#-------------------------------------------------------------------------------------------
AbstractNodeView{T} = Union{NodesView{T},SparseNodesView{T}}
S = AbstractNodeView
view(v::S) = getfield(v, :view)
model(v::S) = getfield(v, :model)
fieldname(v::S) = getfield(v, :fieldname)
N.class(v::S) = v |> view |> class
N.entry(v::S) = v |> view |> entry
network(v::S) = model(v)._value
Base.getproperty(n::S, ::Symbol) = err(n, "no property to access.")
Base.setproperty!(n::S, ::Symbol) = err(n, "no property to access.")
Base.eltype(::Type{S{T}}) where {T} = T
Base.eltype(::S{T}) where {T} = T

#-------------------------------------------------------------------------------------------

# HERE: craft edges views, then build up towards simplifying components def.

# ==========================================================================================
struct Error <: Exception
    type::Type # (View type)
    message::String
end
err(T::Type, m) = throw(Error(T, m))
err(t, m) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))): $(e.message)")

# ==========================================================================================
# Display.

function inline_info(v::NodesView)
    class = V.class(v).name
    field = fieldname(v)
    "<$class:$field>"
end

function inline_info(v::SparseNodesView)
    class = V.class(v).name
    parent = V.parent(v)
    parent = isnothing(parent) ? ":" : parent
    field = fieldname(v)
    "<$parent:$class:$field>"
end

function display_info(v::NodesView)
    T = eltype(v)
    info = inline_info(v)
    "NodesView$info{$T}"
end

function display_info(v::SparseNodesView)
    T = eltype(v)
    info = inline_info(v)
    "SparseNodesView$info{$T}"
end

type_info(::Type{<:NodesView}) = "nodes"
type_info(::Type{<:SparseNodesView}) = "sparse nodes"

function Base.show(io::IO, v::NodesView)
    print(io, inline_info(v))
    print(io, '[')
    read(entry(v)) do raw
        for (i, v) in enumerate(raw)
            print(io, repr(v))
            if i < length(raw)
                print(io, ", ")
            end
        end
    end
    print(io, ']')
end

function Base.show(io::IO, v::SparseNodesView)
    print(io, inline_info(v))
    print(io, '[')
    n = length(v)
    mask = N.mask(network(v), class(v).name, parent(v))
    read(entry(v)) do raw
        i_raw = 0
        for (i_m, m) in enumerate(mask)
            if m
                i_raw += 1
                v = raw[i_raw]
                print(io, repr(v))
            else
                print(io, '·')
            end
            if i_m < n
                print(io, ", ")
            end
        end
    end
    print(io, ']')
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesView)
    print(io, display_info(v))
    (n, s) = ns(length(v))
    print(io, " ($n element$s)")
    read(entry(v)) do raw
        for v in raw
            print(io, "\n ")
            print(io, repr(v))
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::SparseNodesView)
    print(io, display_info(v))
    mask = N.mask(network(v), class(v).name, parent(v))
    (n, _) = ns(length(v))
    read(entry(v)) do raw
        (nz, s) = ns(length(raw))
        print(io, " ($nz/$n element$s)")
        i_raw = 0
        for m in mask
            print(io, '\n')
            if m
                i_raw += 1
                v = raw[i_raw]
                print(io, repr(v))
            else
                print(io, '·')
            end
        end
    end
end

ns(n) = (n, n > 1 ? "s" : "")

end

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
import ..Model
using SparseArrays

const N = Networks
const Option{T} = Union{T,Nothing}

"""
Direct dense view into nodes class data.
"""
struct NodesView{T} <: AbstractVector{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
end
Base.getindex(v::NodesView, i) = getindex(view(v), i)
Base.setindex!(v::NodesView, i, x) = setindex!(view(v), i, x)
nodes_view(m::Model, class::Symbol, data::Symbol) =
    NodesView(m, N.nodes_view(m._value, class, data), data)
export nodes_view

"""
Sparse view into nodes class data,
from the perspective of a superclass.
"""
struct SparseNodesView{T} <: AbstractSparseVector{T,Int}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    restriction::Restriction
    parent::Option{Symbol}
end
function nodes_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}}, data::Symbol)
    r = restriction(m._value, class, parent)
    SparseNodesView(m, N.nodes_view(m._value, class, data), data, r, parent)
end


V{T} = Union{NodesView{T},SparseNodesView{T}}
view(v::V) = getfield(v, :view)
model(v::V) = getfield(v, :model)
fieldname(v::V) = getfield(v, :fieldname)
class(v::V) = v |> view |> N.class
Base.getproperty(n::V, ::Symbol) = err(n, "no property to access.")
Base.setproperty!(n::V, ::Symbol) = err(n, "no property to access.")
Base.eltype(::Type{V{T}}) where {T} = T
Base.eltype(::V{T}) where {T} = T
Base.size(v::V) = size(view(v))

# ==========================================================================================
# Display.

function inline_info(v::NodesView)
    class = Views.class(v).name
    field = fieldname(v)
    "<$class:$field>"
end

function display_info(v::NodesView)
    T = eltype(v)
    class = Views.class(v).name
    field = fieldname(v)
    "NodesView<$class:$field>{$T}"
end

type_info(::Type{<:NodesView}) = "nodes"
type_info(::Type{<:SparseNodesView}) = "sparse nodes"

function Base.show(io::IO, v::NodesView)
    print(io, inline_info(v))
    @invoke show(io, v::AbstractVector)
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesView)
    # Replace type display with custom info.
    s = IOBuffer()
    @invoke show(s, MIME("text/plain"), v::AbstractVector)
    s = String(take!(s))
    target = repr(typeof(v))
    s = replace(s, target => display_info(v))
    print(io, s)
end

# ==========================================================================================
struct Error <: Exception
    type::Type # (View type)
    message::String
end
err(T::Type, m, throw = throw) = throw(Error(T, m))
err(t, m, throw = throw) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))): $(e.message)")
end

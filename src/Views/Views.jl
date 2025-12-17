"""
Types in this module provide protected-yet-ergonomic 'views' into the model data,
with the following intent:

  - Ergonomics:

      + Node-level data behave almost as dense/sparse vectors.
      + Edge-level data behave almost as dense/sparse matrices.
      + Index with class/web local integers.
      + Index with absolute labels symbols.
      + Convenience extraction as proper dense/sparse vectors/matrices.

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

struct Error <: Exception
    type::Type # (View type)
    message::String
end
err(T::Type, m) = throw(Error(T, m))
err(t, m) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))): $(e.message)")

include("nodes.jl")
include("edges.jl")
include("nodes_display.jl")
include("edges_display.jl")

# Base interface for all views.
AbstractView{T} = Union{NodesView{T},ExpandedNodesView{T},EdgesView{T}}
S = AbstractView
view(v::S) = getfield(v, :view)
model(v::S) = getfield(v, :model)
fieldname(v::S) = getfield(v, :fieldname)
N.entry(v::S) = v |> view |> entry
network(v::S) = model(v)._value
Base.getproperty(n::S, ::Symbol) = err(n, "no property to access.")
Base.setproperty!(n::S, ::Symbol) = err(n, "no property to access.")
Base.eltype(::Type{S{T}}) where {T} = T
Base.eltype(::S{T}) where {T} = T

end

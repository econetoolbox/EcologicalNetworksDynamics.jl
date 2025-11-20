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

import ..Networks
import ..Model
const V = Views
const N = Networks

"""
Direct dense view into nodes class data.
"""
struct NodesView{T} <: AbstractVector{T}
    view::N.NodesView{T}
    fieldname::Symbol
    model::Model
end
view(n::NodesView) = getfield(n, :view)
model(n::NodesView) = getfield(n, :model)
fieldname(n::NodesView) = getfield(n, :fieldname)
class(n::NodesView) = n |> view |> N.class
Base.eltype(::Type{NodesView{T}}) where {T} = T
Base.eltype(::NodesView{T}) where {T} = T
Base.getproperty(n::NodesView, _) = err(n, "no property to access.")
Base.setproperty!(n::NodesView, _) = err(n, "no property to access.")
Base.getindex(v::NodesView, i) = getindex(view(v), i)
Base.setindex!(v::NodesView, i, x) = setindex!(view(v), i, x)
Base.size(v::NodesView) = size(view(v))
nodes_view(m::Model, class::Symbol, data::Symbol) =
    NodesView(N.nodes_view(m._value, class, data), data, m)

# ==========================================================================================
# Display.

function inline_info(v::NodesView)
    class = V.class(v).name
    field = fieldname(v)
    "<$class:$field>"
end

function display_info(v::NodesView)
    T = eltype(v)
    class = V.class(v).name
    field = fieldname(v)
    "NodesView<$class:$field>{$T}"
end

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
Base.showerror(io::IO, e::Error) = print(io, "View error ($(e.type)): $(e.message)")

end

"""
Types in this module provide protected-yet-ergonomic 'views' into the model data,
with the following intent:

  - Ergonomics:

      + Node-level data behave almost as dense/sparse vectors.
      + Edge-level data behave almost as dense/sparse matrices.
      + Index with class/web local integers.
      + Index with absolute labels symbols.
      + Convenience extraction as proper, owned dense/sparse vectors/matrices.

  - Protection:

      + Only mutable if the underlying model/network allows it.
      + Enforce underlying COW pattern.
      + Avoids leaking references to underlying data.

Under the hood, not all views work the same,
although they should implement the same interface:

    - Views into internal network mutable *data* associated with nodes and edges
      directly wrap a `Networks.View` along with a reference to its model.
      Refer to them as `DataView`s.

    - Views into network *topology* (node names, edges and restriction binary masks)
      also conceptually wrap data associated with nodes and edges,
      but these are not reified as underlying vectors and are immutable.
      Refer to them as `TopologyView`s and `MaskView`s.
"""
module Views

using SparseArrays

using ..Networks
using ..Framework
using ..Display
import ..Model

const N = Networks
const V = Views
const Option{T} = Union{T,Nothing}
const Ref = Union{Int,Symbol}

struct Error <: Exception
    type::Type # (View type)
    message::String
end
err(T::Type, m) = throw(Error(T, m))
err(t, m) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))): $(e.message)")

"""
Extract an owned copy of the viewed data under a regular dense/sparse vector/matrix form.
"""
function extract end
export extract

include("nodes.jl")
include("edges.jl")
include("nodes_display.jl")
include("edges_display.jl")

# ==========================================================================================
# Common to both nodes and edges.

DataView{T} = Union{AbstractNodesDataView{T},EdgesDataView{T}}
S = DataView
view(v::S) = getfield(v, :view)
fieldname(v::S) = getfield(v, :fieldname)
N.entry(v::S) = v |> view |> entry
Base.eltype(::Type{S{T}}) where {T} = T

AbstractView = Union{NodesView,EdgesView}
S = AbstractView
model(v::S) = getfield(v, :model)
network(v::S) = v |> model |> value
Base.eltype(v::S) = eltype(typeof(v))
Base.getproperty(n::S, ::Symbol) = err(n, "no property to access.")
Base.setproperty!(n::S, ::Symbol) = err(n, "no property to access.")

end

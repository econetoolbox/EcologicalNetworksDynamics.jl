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
although they should implement the same interface (mutability aside):

    - Views into internal network mutable *data* associated with nodes and edges
      directly wrap a `Networks.View` along with a reference to its model.
      Refer to them as `DataView`s.
      These are generic over the (class/web, field) names,
      so this may be used for dispatching field-specific behaviour like value checking.

    - Views into network *topology* (node names, edges and restriction binary masks)
      also conceptually wrap data associated with nodes and edges,
      but these are not reified as underlying vectors and are immutable.
      Refer to them as `TopologyView`s and `MaskView`s.

All views are parametrized with a network config dispatcher
so their behaviour can be fine-tuned by downstream component authors.
"""
module Views

using SparseArrays
using Crayons

using ..Networks
using ..Framework
using ..Display
import ..Model
import ..NetworkConfig

const N = Networks
const V = Views
const C = NetworkConfig
const Option{T} = Union{T,Nothing}
const Ref = Union{Int,Symbol}

struct Error <: Exception
    type::Type # (View type)
    message::String
end
err(T::Type, m) = throw(Error(T, m))
err(t, m, throw = throw) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))): $(e.message)")

"""
Extract an owned copy of the viewed data under a regular dense/sparse vector/matrix form.
"""
function extract end
export extract

# TODO: feature indexing into views with `::Colon` e.g. `views[:a, :]`.

include("nodes.jl")
include("edges.jl")
include("nodes_display.jl")
include("edges_display.jl")

# ==========================================================================================
# Common nodes or edge data views.

DataView{d,T} = Union{AbstractNodesDataView{d,T},EdgesDataView{d,T}}
S = DataView
view(v::S) = getfield(v, :view)
fieldname(s::S) = C.data(dispatcher(s))
N.entry(v::S) = v |> view |> entry

struct WriteError <: Exception
    message::String
    fieldname::Symbol
    index::Any
    value::Any
end
function Base.showerror(io::IO, e::WriteError)
    (; fieldname, index, value, message) = e
    it, reset = crayon"italics", crayon"reset"
    print(
        io,
        "Cannot set node data $fieldname$(display_index(index)):\n\
         $it  $message$reset\n\
         Received value: $(repr(value)) ::$(typeof(value))",
    )
end
display_index(i...) = display_index(i)
display_index(i::Tuple) = "[$(join(repr.(i), ", "))]"

# ==========================================================================================
#  Common to all views.

AbstractView{d} = Union{NodesView{d},EdgesView{d}}
S = AbstractView
dispatcher(::Type{S{d}}) where {d} = d
dispatcher(s::S) = dispatcher(typeof(s))
model(v::S) = getfield(v, :model)
network(v::S) = v |> model |> value
Base.getproperty(n::S, ::Symbol) = err(n, "no property to access.")
Base.setproperty!(n::S, ::Symbol) = err(n, "no property to access.")

end

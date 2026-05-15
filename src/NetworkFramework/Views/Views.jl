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

    - Views into network *topology* (node names, edges and restriction binary masks)
      also conceptually wrap data associated with nodes and edges,
      but these are not reified as underlying vectors and are immutable.
      Refer to them as `TopologyView`s and `MaskView`s.

View types are parametrized with a dispatcher
so their behaviour can be fine-tuned by downstream component authors.
"""
module Views

# A lot of small accessors are defined and used within this module.
# Namespace them with the module of their expected *result*.
# For instance: `D.class(view)` will result in a symbol
# while `N.class(view)` will result in the actual underlying class value.
# A lot of them are also shared among different types of views.
# Use the following pattern to avoid having to heavily duplicate them:
#
#    # Anything specific to (1).
#    struct ViewType1 ... end
#    S = ViewType1 # "Self"
#    method1(s::S) = ...
#
#    # Anything specific to (2).
#    struct ViewType2 ... end
#    S = ViewType2 # "Self"
#    method2(s::S) = ...
#
#    # Anything common to both.
#    S = Union{ViewType1,ViewType2}
#    method3(s::S) = ...
#    ...
#
# This makes the code easier to navigate and maintain,
# /!\ at the cost of confusing `Revise` very much.
# Don't expect Revise to correctly track changes within this module because of this.
# But I still think it's worth the cost.

import EcologicalNetworksDynamics: EN, N, F, I, NetworkFramework, Display, Option
import .NetworkFramework: NF, D, Model, Ref
const V = Views

using SparseArrays
using Crayons

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
N.view(v::S) = getfield(v, :view)
D.field(s::S) = D.field(dispatcher(s))
N.entry(v::S) = v |> N.view |> N.entry

# ==========================================================================================
#  Common to all views.

AbstractView{d} = Union{NodesView{d},EdgesView{d}}
S = AbstractView
dispatcher(::Type{<:S{d}}) where {d} = d
dispatcher(s::S) = s |> typeof |> dispatcher
D.readonly(s::S) = s |> dispatcher |> D.readonly
D.type(s::S) = s |> dispatcher |> D.type
NF.model(s::S) = getfield(s, :model)
N.network(s::S) = s |> NF.model |> N.network
Base.getproperty(s::S, ::Symbol) = err(s, "no property to access.")
Base.setproperty!(s::S, ::Symbol) = err(s, "no property to access.")

# Delegate indexing to native abstract arrays unless we get really unexpected types.
check_ref(::S, r::Ref) = r
check_ref(::S, u::UnitRange) = u
check_ref(::S, c::CartesianIndex) = c
check_ref(s::S, x::Any) = err(
    s,
    "Views are indexed with indices (::Int) or labels (::Symbol). \
     Cannot index with: $(repr(x)) ::$(typeof(x)).",
)

# ==========================================================================================
# Dedicated view exception.

struct Error <: Exception
    type::Type # (View type)
    mess::String
end
err(T::Type, m) = throw(Error(T, m))
err(t, m, throw = throw) = throw(Error(typeof(t), m))
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))):\n$(e.mess)")

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
         $it$message$reset\n\
         Received value: $(repr(value)) ::$(typeof(value))",
    )
end
display_index(i...) = display_index(i)
display_index(i::Tuple) = "[$(join(repr.(i), ", "))]"

end

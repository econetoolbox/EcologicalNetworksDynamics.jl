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

    - Views into internal network mutable associated with nodes and edges *fields*
      directly wrap a `Networks.View` along with a reference to its model.
      Refer to them as `FieldView`s.

    - Views into network *topology* (node names, edges and restriction binary masks)
      also conceptually wrap data associated with nodes and edges,
      but these are not reified as underlying vectors and are immutable.
      Refer to them as `TopologyView`s and `MaskView`s.

View types are parametrized with a matching selector
so their behaviour can be fine-tuned by downstream component authors.
"""
module Views

import EcologicalNetworksDynamics:
    EN, ST, CS, I, Storage, NetworkFramework, Option, Display, SparseMatrix, errwith, argerr
import .Display: join_elided, render_input, ns, reset, cyan, green, yellow, nsa
import .NetworkFramework:
    NF, SL, Model, can_convert, CheckError, checkerr, LibError, selector, Ref,
    wholedata, WholeData, UserRef, ModelRef
const VW = Views

using SparseArrays
using Crayons

# A lot of small accessors are defined and used within this module.
# Namespace them with the module of their expected *result*.
# For instance: `SL.class(view)` will result in a symbol
# while `N.class(view)` will result in the actual underlying class value.
# A lot of them are also shared among different types of views.
# Use the following pattern to avoid having to heavily duplicate them:
#
#    # Anything specific to (1).
#    struct ViewType1 ... end
#    let S = ViewType1 # "Self"
#      method1(s::S) = ...
#    end
#
#    # Anything specific to (2).
#    struct ViewType2 ... end
#    let S = ViewType2 # "Self"
#      method2(s::S) = ...
#    end
#
#    # Anything common to both.
#    let S = Union{ViewType1,ViewType2} # "Self"
#      method3(s::S) = ...
#    end
#
#    ...
#
# This makes the code easier to navigate and maintain,
# /!\ at the cost of confusing `Revise` very much.
# Don't expect Revise to correctly track changes within this module because of this.
# But I still think the readability/mantainability gain it's worth that cost.

"Extract an owned copy of the viewed data under a regular dense/sparse vector/matrix form."
function extract end
export extract

"Extract an owned copy of the viewed data as a sparse array within parent class."
function spextract end
export spextract

include("nodes.jl")
include("edges.jl")

# Common to all topology-related = immutable views.
const TopologyView{s} = Union{NodeTopologyView{s},EdgeMaskView{s}}

# Common to nodes or edge field views.
const FieldView{s,T} = Union{NodeFieldView{s,T},EdgeFieldView{s,T}}
let V = FieldView
    SL.fieldname(v::V) = v |> selector |> SL.fieldname # Associated fieldname.
    ST.view(v::V) = getfield(v, :view) # Underlying network data view.
    ST.entry(v::V) = v |> ST.view |> ST.entry # Corresponding entry.
end

#  Common to all views.
const AbstractView{s} = Union{NodeView{s},EdgeView{s}}
let V = AbstractView
    # Extract selector and delegate some basic selector interface.
    NF.selector(::Type{<:V{s}}) where {s} = s
    NF.selector(v::V) = v |> typeof |> selector
    SL.readonly(v::V) = v |> selector |> SL.readonly
    SL.type(v::V) = v |> selector |> SL.type

    # Underlying model and network.
    NF.model(v::V) = getfield(v, :model)
    ST.network(v::V) = v |> NF.model |> ST.network

    # Forbid any property access.
    Base.setproperty!(v::V, y::Symbol) = getproperty(v, y)
    Base.getproperty(::V, s::Symbol) =
        errwith("No property to access on views:") do io
            print(io, "Tried to access $cyan$(repr(s))$reset.")
        end
end

include("nodes_display.jl")
include("edges_display.jl")

# ==========================================================================================
# Julia `getindex` endpoint.

include("query.jl")

function Base.getindex(vw::AbstractView, query...)
    # (Pretty-much hand-made dispatching, right?)
    md, s = NF.model(vw), selector(vw)
    # Check whether we have specialized for this query type,
    # or else just resort to AbstractArray implementation.
    ref = if applicable(_query_check, vw, query)
        _query_check(vw, query)
    else
        P = supertype(typeof(vw))
        return invoke(getindex, Tuple{P,Vararg}, vw, query...)
    end
    # Same here, either there is specialization how to obtain the value
    # or we just loop back in with the checked query.
    if applicable(NF.obtain, vw, ref)
        NF.obtain(vw, ref)
    elseif applicable(NF.obtain, md, s, ref)
        NF.obtain(md, s, ref)
    else
        # .. careful though.
        if typeof(ref) == typeof(query)
            fn = "$NF.$(NF.obtain)"
            V = typeof(vw)
            Q = typeof(query)
            errwith("Preventing infinite loop?") do io
                print(io, "Forgot to implement $fn($V, $Q)?")
            end
        end
        getindex(vw, ref...)
    end
end

#-------------------------------------------------------------------------------------------
# Julia `setindex!` endpoint.

"Mutate fields through the view."
function Base.setindex!(vw::FieldView, rhs, query...)
    SL.readonly(vw) && throw(ImmutableError(typeof(vw)))
    ref = if applicable(_query_check, vw, query)
        _query_check(vw, query)
    else
        P = supertype(typeof(vw))
        R = typeof(rhs)
        return invoke(setindex!, Tuple{P,R,Vararg}, vw, rhs, query...)
    end
    _mut_set!(vw, ref, rhs)
end
# Circle back as long as the ref is not just two local integers.
_mut_set!(vw::FieldView, ref, rhs) = setindex!(vw, rhs, ref...)
_mut_set!(vw::FieldView, ref::NF.TrustedIndexRef, rhs) =
    NF.mut_set!(NF.model(vw), selector(vw), ref, rhs)

"Views into topological information cannot be used to mutate it."
Base.setindex!(vw::TopologyView, _...) = throw(ImmutableError(typeof(vw)))

struct ImmutableError <: LibError
    V::Type{<:AbstractView}
end

function Base.showerror(io::IO, e::ImmutableError)
    (; V) = e
    i = type_info(V)
    s = selector(V)
    print(io, "Cannot change $s $i once they have been set.")
end

end

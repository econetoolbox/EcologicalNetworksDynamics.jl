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

View types are parametrized with a matching dispatcher
so their behaviour can be fine-tuned by downstream component authors.
"""
module Views

import EcologicalNetworksDynamics:
    EN, N, F, I, Networks, NetworkFramework, Option, Display, SparseMatrix, errwith
import .Display: join_elided, render_input, ns, reset, cyan, yellow, nsa
import .NetworkFramework:
    NF, D, Model, can_convert, CheckError, checkerr, LibError, dispatcher, Ref,
    WholeData, _WholeData
const V = Views

using SparseArrays
using Crayons

# A lot of small accessors are defined and used within this module.
# Namespace them with the module of their expected *result*.
# For instance: `D.class(view)` will result in a symbol
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

"""
Extract an owned copy of the viewed data under a regular dense/sparse vector/matrix form.
"""
function extract end
export extract

include("nodes.jl")
include("edges.jl")

# Common to all topology-related = immutable views.
const TopologyView{d} = Union{NodeTopologyView{d},EdgeMaskView{d}}

# Common to nodes or edge field views.
const FieldView{d,T} = Union{AbstractNodeFieldView{d,T},EdgeFieldView{d,T}}
let S = FieldView
    D.field(s::S) = s |> dispatcher |> D.field # Associated fieldname.
    N.view(s::S) = getfield(s, :view) # Underlying network data view.
    N.entry(s::S) = s |> N.view |> N.entry # Corresponding entry.
end

#  Common to all views.
const AbstractView{d} = Union{NodeView{d},EdgeView{d}}
let S = AbstractView
    # Extract dispatcher and delegate some basic dispatcher interface.
    NF.dispatcher(::Type{<:S{d}}) where {d} = d
    NF.dispatcher(s::S) = s |> typeof |> dispatcher
    D.readonly(s::S) = s |> dispatcher |> D.readonly
    D.type(s::S) = s |> dispatcher |> D.type

    # Underlying model and network.
    NF.model(s::S) = getfield(s, :model)
    N.network(s::S) = s |> NF.model |> N.network

    # Forbid any property access.
    Base.setproperty!(s::S, y::Symbol) = getproperty(s, y)
    Base.getproperty(::S, s::Symbol) =
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
    md, d = NF.model(vw), dispatcher(vw)
    # Check whether we have specialized for this query type,
    # or else just resort to AbstractArray implementation.
    mref = if applicable(_query_check, vw, query)
        _query_check(vw, query)
    else
        P = supertype(typeof(vw))
        return invoke(getindex, Tuple{P,Vararg}, vw, query...)
    end
    # Same here, either we have explained how to obtain the value
    # or we just loop back in with the checked query.
    if applicable(NF.obtain, vw, mref)
        NF.obtain(vw, mref)
    elseif applicable(NF.obtain, md, d, mref)
        NF.obtain(md, d, mref)
    else
        # .. careful though.
        if typeof(mref) == typeof(query)
            fn = "$NF.$(NF.obtain)"
            V = typeof(vw)
            Q = typeof(query)
            throw("Preventing infinite loop? Forgot to implement $fn($V, $Q)?")
        end
        getindex(vw, mref...)
    end
end

#-------------------------------------------------------------------------------------------
# Julia `setindex!` endpoint.

"Mutate fields through the view."
function Base.setindex!(vw::FieldView, rhs, query...)
    mref = if applicable(_query_check, vw, query)
        _query_check(vw, query)
    else
        P = supertype(typeof(vw))
        R = typeof(rhs)
        return invoke(setindex!, Tuple{P,R,Vararg}, vw, rhs, query...)
    end
    _mut_set!(vw, mref, rhs)
end
# Circle back as long as the mref is not just two local integers.
_mut_set!(vw::FieldView, mref, rhs) = setindex!(vw, rhs, mref...)
_mut_set!(vw::FieldView, mref::NF.TrustedMRef, rhs) =
    NF.mut_set!(NF.model(vw), dispatcher(vw), mref, rhs)

"Views into topological information cannot be used to mutate it."
Base.setindex!(vw::TopologyView, _...) = throw(ImmutableError(typeof(vw)))

struct ImmutableError <: LibError
    V::Type{<:AbstractView}
end

function Base.showerror(io::IO, e::ImmutableError)
    (; V) = e
    i = type_info(V)
    d = dispatcher(V)
    print(io, "Cannot change $d $i once they have been set.")
end

end

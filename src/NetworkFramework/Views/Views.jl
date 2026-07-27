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

import EcologicalNetworksDynamics:
    EN, N, F, I, Networks, NetworkFramework, Display, Option, join_elided, render_input
import .NetworkFramework: NF, D, Model
const V = Views

using SparseArrays
using Crayons

"""
Extract an owned copy of the viewed data under a regular dense/sparse vector/matrix form.
"""
function extract end

# TODO: watch https://github.com/JuliaEditorSupport/JuliaFormatter.jl/issues/1203
"""
Obtain underlying view dispatcher.
"""
function dispatcher end

include("errors.jl")
include("nodes.jl")
include("edges.jl")
include("nodes_display.jl")
include("edges_display.jl")

# ==========================================================================================
# Common to nodes or edge field views.

FieldView{d,T} = Union{AbstractNodeFieldView{d,T},EdgeFieldView{d,T}}
let S = FieldView
    D.field(s::S) = s |> dispatcher |> D.field # Associated fieldname.
    N.view(s::S) = getfield(s, :view) # Underlying network data view.
    N.entry(s::S) = s |> N.view |> N.entry # Corresponding entry.
end

# ==========================================================================================
#  Common to all views, including 'virtual' ones into topology.

AbstractView{d} = Union{NodeView{d},EdgeView{d}}
let S = AbstractView
    # Extract dispatcher and delegate some basic dispatcher interface.
    V.dispatcher(::Type{<:S{d}}) where {d} = d
    V.dispatcher(s::S) = s |> typeof |> dispatcher
    D.readonly(s::S) = s |> dispatcher |> D.readonly
    D.type(s::S) = s |> dispatcher |> D.type

    # Underlying model and network.
    NF.model(s::S) = getfield(s, :model)
    N.network(s::S) = s |> NF.model |> N.network

    # Forbid any property access.
    Base.getproperty(s::S, ::Symbol) = qerr(s, "no property to access.")
    Base.setproperty!(s::S, ::Symbol) = qerr(s, "no property to access.")
end

include("indexing.jl")

end

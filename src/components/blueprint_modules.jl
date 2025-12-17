# XXX: file on hold.
# Factorize numerous imports useful within the blueprint submodules.
# To be `include`d from these modules.

using SparseArrays
using OrderedCollections

using EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
const F = EcologicalNetworksDynamics.Framework
import .EN:
    AliasingDicts,
    Blueprint,
    SparseMatrix,
    check_template,
    check_value,
    dense_nodes_allometry,
    sparse_edges_allometry,
    sparse_nodes_allometry,
    @get,
    @ref
import .F: @blueprint, checkfails, Brought, checkrefails

using .EN.Networks
using .EN.AliasingDicts
using .EN.AllometryApi
using .EN.GraphDataInputs
using .EN.KwargsHelpers

const I = Iterators
const Option{T} = Union{T,Nothing}

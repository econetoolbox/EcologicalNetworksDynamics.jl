# Factorize numerous imports useful within the blueprint submodules.
# To be `include`d from these modules.

using SparseArrays
using EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
const F = EcologicalNetworksDynamics.Framework
import .EN:
    AliasingDicts,
    Blueprint,
    Internals,
    Option,
    SparseMatrix,
    Topologies,
    check_template,
    check_value,
    dense_nodes_allometry,
    imap,
    sparse_edges_allometry,
    sparse_nodes_allometry,
    @get,
    @ref
import .F: @blueprint, checkfails, Brought, checkrefails
using .EN.AliasingDicts
using .EN.AllometryApi
using .EN.GraphDataInputs
using .EN.KwargsHelpers
using .EN.Topologies
using OrderedCollections

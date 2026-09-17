"""
Test error reports on incorrect indexing within views.
"""
module IndexingGuards

using EcologicalNetworksDynamics
using SparseArrays

using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, F, D, Network, Views
import Main: is_repr, is_disp, @inputfails, @sysfails, @queryfails, Value

setprefix = "Indexing guards: "

# Assuming 3 nodes "abc".
function check_node_guards(v, View::Type)

    #---------------------------------------------------------------------------------------
    # Off-level dimension.

    @queryfails(v[], View, false, "Node-level data has 1 dimension, received 0")
    @queryfails(v[1, :a], View, false, "Node-level data has 1 dimension, received 2")
    @queryfails(
        v[0x1, 'a', nothing],
        View,
        false,
        "Node-level data has 1 dimension, received 3"
    )

    #---------------------------------------------------------------------------------------
    # Off-type.
    @queryfails(
        v[nothing],
        View,
        false,
        "Views are queried with indices [::Int] or labels [::Symbol]"
    )
    @queryfails(v[0], View, true, "Integer node references can only be positive")
    @queryfails(v[0:2], View, true, "Integer node references can only be positive")
    @queryfails(
        v['a':'c'],
        View,
        false,
        "Views are queried with indices [::Int] or labels [::Symbol]"
    )
    @queryfails(
        v[[1, 0, 2]],
        View,
        false,
        "Could not interpret as a boolean mask (not only 1's and 0's?)"
    )
    @queryfails(
        v[[nothing, "wrongtypes"]],
        View,
        false,
        "Views are queried with indices [::Int] or labels [::Symbol]"
    )

    #---------------------------------------------------------------------------------------
    # Off-class.

    @queryfails(v[4], View, true, "This class only contains 3 nodes")
    @queryfails(v[:x], View, true, "No node in this class is labeled :x")
    @queryfails(v[end:(end+1)], View, true, "This class only contains 3 nodes")
    @queryfails(
        v[[true, false]],
        View,
        true,
        "The given mask is of size 2 but there are 3 nodes in the class"
    )
end

@testset "$setprefix node names" begin
    m = Model(Species(:a, :b, :c))
    v = m.species.names
    View = Views.NodeNameView{D.Class(:species)}
    check_node_guards(v, View)
end

@testset "$setprefix subnode mask" begin
    m = Model(Species(:a, :b, :c))
    v = m.species.mask
    View = Views.NodeMaskView{D.Subclass(:species, nothing)}
    check_node_guards(v, View)
end

end

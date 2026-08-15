"""
Test all aspects of typical Subclass component, using producers as an example.
"""
module SubclassTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, F, D, Network, Views
import Main: is_repr, is_disp, @inputfails, @sysfails, @indexfails, Value
const View = Views.NodeNameView{D.Class(:species)} # Tested view type.

@testset "Subclass component: views" begin

    m = Model(Foodweb([:a => (:b, :c), :d => :e]))

    # Views are restricted within the parent component.
    @test m.producers.names == [:b, :c, :e]
    @test m.producers.number == 3
    @test m.producers.index == OrderedDict(:b => 1, :c => 2, :e => 3)
    @test m.producers.parent_index == OrderedDict(:b => 2, :c => 3, :e => 5)
    k = m.producers.mask
    @test k == [0, 1, 1, 0, 1]
    @test k[2:4] == [1, 1, 0]

end

end

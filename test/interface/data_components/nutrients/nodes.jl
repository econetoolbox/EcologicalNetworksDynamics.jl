module NodesTests

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: ST
using Test

@testset "Nutrients.Nodes." begin

    @test Nutrients isa Module
    @test Nutrients.Nodes isa Component

    m = Model(Nutrients.Nodes(3))
    @test m.nutrients.names == [:n1, :n2, :n3]

    # A web automatically appears between producers and them.
    m += Foodweb([:a => [:b, :c]])
    @test size(ST.network(m).webs[:nutrients_producers]) == (2, 3)

end

end

module ConcentrationTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails, addfails
using Test

const s, S = SL.EdgeField(:nutrients_producers, :concentration)

@testset "Nutrients.Concentration" begin

    @test Nutrients.Concentration isa Component
    @bpfails(Nutrients.Concentration([-5]), Nutrients.Concentration.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    base = Model(Foodweb([:a => [:b, :c]]), Nutrients.Nodes(3))
    m = base + Nutrients.Concentration(5)
    @test m.nutrients.concentration == m.nutrients_producers.concentration == [
        5 5 5
        5 5 5
    ]

    addfails.@missing(Model(Foodweb([]), Nutrients.Concentration([5])),
        Nutrients.Nodes, Nutrients.Concentration, [Nutrients.Concentration.Raw], nothing)
    addfails.@missing(Model(Nutrients.Nodes(3), Nutrients.Concentration([5])),
        Foodweb, Nutrients.Concentration, [Nutrients.Concentration.Raw], nothing)

end

end

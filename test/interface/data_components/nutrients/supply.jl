module SupplyTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.NodeField(:nutrients, :supply)

@testset "Nutrients.Supply." begin

    @test Nutrients.Supply isa Component
    @test fieldnames(Nutrients.Supply.Raw) == (:t,)
    @test fieldtypes(Nutrients.Supply.Flat) == (Float64,)
    @bpfails(Nutrients.Supply([-5]), Nutrients.Supply.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    m = Model(Nutrients.Supply([4,5,6]))
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.supply == [4, 5, 6]

end

end

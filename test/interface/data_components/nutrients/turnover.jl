module TurnoverTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.NodeField(:nutrients, :turnover)

@testset "Nutrients.Turnover." begin

    @test Nutrients.Turnover isa Component
    @test fieldnames(Nutrients.Turnover.Raw) == (:t,)
    @test fieldtypes(Nutrients.Turnover.Flat) == (Float64,)
    @bpfails(Nutrients.Turnover([-5]), Nutrients.Turnover.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    m = Model(Nutrients.Turnover([4,5,6]))
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.turnover == [4, 5, 6]

end

end

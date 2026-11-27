module ConsumptionRateTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.NodeField(:consumers, :consumption_rate)

@testset "ConsumptionRate." begin

    # Not much to test, this is a pretty regular component yet.
    @test ConsumptionRate isa Component
    @bpfails(ConsumptionRate([-5]), ConsumptionRate.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    m = Model(Foodweb([:a => :b, :b => :c]), ConsumptionRate(5))
    @test m.alpha == m.consumers.consumption_rate == [5, 5]
    @test spextract(m.alpha) == [5, 5, 0]

end

end

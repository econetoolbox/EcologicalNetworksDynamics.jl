module HalfSaturationDensityDef

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.NodeField(:consumers, :half_saturation_density)

@testset "HalfSaturationDensity." begin

    # Not much to test, this is a pretty regular component yet.
    @test HalfSaturationDensity isa Component
    @bpfails(HalfSaturationDensity([-5]), HalfSaturationDensity.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    m = Model(Foodweb([:a => :b, :b => :c]), HalfSaturationDensity(5))
    @test m.half_saturation_density == [5, 5]
    @test spextract(m.half_saturation_density) == [5, 5, 0]

end

end

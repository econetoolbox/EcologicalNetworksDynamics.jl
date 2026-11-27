module IntraspecificInterferenceTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.NodeField(:consumers, :intraspecific_interference)

@testset "IntraspecificInterference." begin

    # Not much to test, this is a pretty regular component yet.
    @test IntraspecificInterference isa Component
    @bpfails(IntraspecificInterference([-5]), IntraspecificInterference.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    m = Model(Foodweb([:a => :b, :b => :c]), IntraspecificInterference(5))
    @test m.consumers.intraspecific_interference == [5, 5]
    @test spextract(m.consumers.intraspecific_interference) == [5, 5, 0]

end

end

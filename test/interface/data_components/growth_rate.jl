module GrowthRateTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, SparseVector, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:producers, :growth)

@testset "GrowthRate." begin

    @test GrowthRate isa Component
    @bpfails(GrowthRate(-1),
        GrowthRate.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c], :b => :c]))
    m = base + GrowthRate([5, 8])
    @test m.growth_rate == m.producers.growth == [5, 8] # Convenience alias.
    @test spextract(m.growth_rate) isa SparseVector{Float64}
    @test spextract(m.growth_rate) == [0, 0, 5, 8]

    # From allometric rates.
    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)

    bp = GrowthRate.Allometric(:Miele2019)
    @test bp == GrowthRate(:Miele2019)
    @test_repr(bp.allometry, "Allometry(p: (a: 1.0, b: -0.25), i: (), e: ())")
    m = base + bp
    @test m.growth_rate == [1, 1]

    # With temperature.
    a = 1.5497531357028967e-7
    bp = GrowthRate.Temperature(:Binzer2016)
    @test bp == GrowthRate(:Binzer2016)
    @test_repr(bp.allometry, "Allometry(p: (a: $a, b: -0.25), i: (), e: ())")
    m = base + Temperature(; celc = 20) + bp
    @test m.growth_rate ≈ [a, a]

end

end

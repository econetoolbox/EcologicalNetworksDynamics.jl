module GrowthTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, SparseVector, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:producers, :growth)

@testset "Growth." begin

    @test Growth isa Component
    @bpfails(Growth(-1),
        Growth.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c], :b => :c]))
    m = base + Growth([5, 8])
    @test m.r == m.producers.growth == [5, 8] # Convenience alias.
    @test spextract(m.r) isa SparseVector{Float64}
    @test spextract(m.r) == [0, 0, 5, 8]

    # From allometric rates.
    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)

    bp = Growth.Allometric(:Miele2019)
    @test bp == Growth(:Miele2019)
    @test_repr(bp.allometry, "Allometry(p: (a: 1.0, b: -0.25), i: (), e: ())")
    m = base + bp
    @test m.r == [1, 1]

    # With temperature.
    a = 1.5497531357028967e-7
    bp = Growth.Temperature(:Binzer2016)
    @test bp == Growth(:Binzer2016)
    @test_repr(bp.allometry, "Allometry(p: (a: $a, b: -0.25), i: (), e: ())")
    m = base + Temperature(; celc = 20) + bp
    @test m.r ≈ [a, a]

end

end

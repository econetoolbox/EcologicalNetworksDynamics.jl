module MetabolismTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:species, :metabolism)

@testset "Metabolism." begin

    @test Metabolism isa Component
    @bpfails(Metabolism(-1),
        Metabolism.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c], :b => :c]))
    m = base + Metabolism([4, 5, 6, 7])
    @test m.x == m.species.metabolism == [4, 5, 6, 7] # Convenience alias.

    # From allometric rates.
    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)

    bp = Metabolism.Allometric(:Miele2019)
    @test bp == Metabolism(:Miele2019)
    @test_repr(bp.allometry,
        "Allometry(p: (a: 0.0, b: 0.0), i: (a: 0.314, b: -0.25), e: (a: 0.88, b: -0.25))")
    m = base + bp
    @test m.x == [0.314, 0.314, 0, 0]

    # With temperature.
    a = 6.557967639824989e-8
    bp = Metabolism.Temperature(:Binzer2016)
    @test bp == Metabolism(:Binzer2016)
    @test_repr(bp.allometry, "Allometry(\
               p: (a: 0.0, b: -0.31), \
               i: (a: $a, b: -0.31), \
               e: (a: $a, b: -0.31))")
    m = base + Temperature() + bp
    @test m.x ≈ [a, a, 0, 0]

    # Rescuing older tests to try non-degenerated cases
    base = Model(
        Foodweb([:a => [:b, :c], :b => :c]),
        BodyMass(1.5),
        MetabolicClass(:all_invertebrates),
    )
    m = base + Metabolism(:Miele2019)
    @test m.x ≈ [0.2837310291334913, 0.2837310291334913, 0.0]
    m = base + Temperature(; celc = 20) + Metabolism(:Binzer2016)
    @test m.x == [5.7833700154794104e-8, 5.7833700154794104e-8, 0.0]

end

end

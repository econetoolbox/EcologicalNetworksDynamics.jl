module MortalityTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:species, :mortality)

@testset "Mortality." begin

    # Mostly duplicated from Growth.
    @test Mortality isa Component
    @bpfails(Mortality(-1),
        Mortality.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))
    m = base + Mortality([5, 8, 13])
    @test m.d == m.mortality == [5, 8, 13]

    # From allometry.
    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)
    bp = Mortality.Allometric(:Miele2019)
    @test bp == Mortality(:Miele2019)
    @test_repr(bp.allometry,
        "Allometry(p: (a: 0.0138, b: -0.25), \
                   i: (a: 0.0314, b: -0.25), \
                   e: (a: 0.0314, b: -0.25))")
    m = base + bp
    @test m.mortality ≈ [0.0314, 0.0314, 0.0138]

    # Rescued old test to try a non-degenerated case.
    m = Model(
        Foodweb([:a => [:b, :c], :b => :c]),
        BodyMass(1.5),
        MetabolicClass(:all_invertebrates),
        Mortality(:Miele2019)
    )
    @test m.mortality == [0.028373102913349126, 0.028373102913349126, 0.012469707649815859]
end

end

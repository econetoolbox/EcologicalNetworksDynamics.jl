module GrowthRateTest

using EcologicalNetworksDynamics

using Test

@testset "GrowthRate component." begin

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))
    m = base + GrowthRate([4])

    # Convenience view alias.
    @test m.growth_rate == m.producers.growth == [0, 0, 4]

    # From allometric rates.
    bp = GrowthRate.Allometric(:Miele2019)
    @test bp == GrowthRate(:Miele2019)

    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)
    m = base + bp
    m.growth_rate == [0, 0, 1]

    # From temperature.
    bp = GrowthRate.Temperature(:Binzer2016)
    @test bp == GrowthRate(:Binzer2016)
    m = base + Temperature(298.5) + bp
    @test m.growth_rate ≈ [0, 0, 2.812547966878026e-7]

end

end

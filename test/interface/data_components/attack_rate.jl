module AttackRateDef

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

# Extra component defined for the the particular AttackRate.Miele2019.
@testset "Mobility." begin

    s, S = SL.NodeField(:species, :mobility)

    @test Mobility isa Component
    @test Mobility.Miele2019 <: Blueprint

    # Early check.
    @bpfails(Mobility([:x]),
        Mobility.Raw, :construct,
        (s, :x, (:u, (1,)), "Expected one of :sessile or :mobile."))

    @test fieldnames(Mobility.Miele2019) == ()
    bp = Mobility.Miele2019()
    @test bp == Mobility() # Default.

    base = Model(Foodweb([:a => :b, :c => :d]))
    m = base + bp
    @test eltype(m.mobility) === Symbol
    @test m.mobility == [:mobile, :sessile, :mobile, :sessile]

end

@testset "AttackRate." begin

    s, S = SL.EdgeField(:trophic, :attack_rate)

    @test AttackRate isa Component
    # Early check.
    @bpfails(AttackRate([-5]), AttackRate.Raw, :construct,
        (s, -5.0, (:u, (1,)), "Value cannot be negative."))

    # Construct from mobility.
    @test AttackRate.Miele2019 <: Blueprint
    @test fieldnames(AttackRate.Miele2019) == ()
    bp = AttackRate.Miele2019()

    base = Model(Foodweb([:a => :b, :b => :c]), BodyMass(; Z = 1))
    m = base + bp
    @test m.attack_rate == [
        0 5 0
        0 0 5
        0 0 0
    ] * 10

    # Mobility has been implied then.
    @test has_component(m, Mobility)
    @test m.mobility == [:mobile, :mobile, :sessile]

    # From temperature allometry.
    base = Model(Foodweb([:a => [:b, :c], :b => :c]), BodyMass(; Z = 1))
    @test AttackRate.Temperature <: Blueprint
    bp = AttackRate.Temperature(:Binzer2016)
    @test bp.E_a == -0.38
    @test bp.allometry[:i][:a] == exp(-13.1)
    @test bp.allometry[:e][:c] == -0.8
    base += MetabolicClass(:all_invertebrates) + Temperature(298.5)
    m = base + bp
    a = 2.678153116108099e-6
    @test m.attack_rate ≈ [
        0 a a
        0 0 a
        0 0 0
    ]


end

end

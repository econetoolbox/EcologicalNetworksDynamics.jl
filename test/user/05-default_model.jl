module TestDefaultModel

using EcologicalNetworksDynamics
using Test

Value = EcologicalNetworksDynamics.Internal # To make @sysfails work.
import ..Main: @sysfails, @argfails

@testset "Default model." begin

    fw = Foodweb([:a => (:b, :c), :b => (:c, :d)])

    # Full-fledged default model.
    m = default_model(fw)

    # All components required for simulation have been set.
    @test has_component(m, ProducerGrowth)
    @test has_component(m, FunctionalResponse)
    @test has_component(m, Metabolism)
    @test has_component(m, Mortality)

    # And in particular:
    @test has_component(m, LogisticGrowth)
    @test has_component(m, BioenergeticResponse)

    # Override default values
    @test m.r == [0, 0, 1, 1]
    @test m.K == [0, 0, 1, 1]
    m = default_model(fw, GrowthRate([0, 0, 2, 3]))
    @test m.r == [0, 0, 2, 3]
    @test m.K == [0, 0, 1, 1] # Unchanged.

    # Override default body mass.
    m = default_model(fw, BodyMass(1.5))
    @test m.growth_rate ≈ [0, 0, 0.9036020036098449, 0.9036020036098449] # Allometry update.
    @test m.K ≈ [0, 0, 1, 1]

    # Override default allometric rates.
    m = default_model(fw, BodyMass(1.5), GrowthRate.Allometric(; a_p = 0.5, b_p = 0.8))
    @test m.growth_rate ≈ [0, 0, 0.6915809336112958, 0.6915809336112958]
    @test m.K == [0, 0, 1, 1]

    # Pick another functional response.
    m = default_model(fw, ClassicResponse())
    @test has_component(m, ClassicResponse)
    @test maximum(m.attack_rate) ≈ 334.1719587843073

    # Pick yet another functional response.
    m = default_model(fw, LinearResponse())
    @test has_component(m, LinearResponse)
    @test m.alpha == [1, 1, 0, 0]

    # Switch to temperature-dependent defaults.
    m = default_model(fw, Temperature(290))
    @test has_component(m, LogisticGrowth)
    @test has_component(m, ClassicResponse)
    g = 1.0799310794944612e-7
    @test m.T == 290
    @test m.growth_rate ≈ [0, 0, g, g]

    # Opt-out of some default components.
    m = default_model(fw; without = ProducerGrowth)
    @test !has_component(m, LogisticGrowth)
    @test !has_component(m, ProducerGrowth)
    @sysfails(
        m.r,
        Property(r, "Component <$GrowthRate> is required to read this property.")
    )

    # Still, add it later.
    m += LogisticGrowth(; r = 2, K = 4)
    @test m.r == [0, 0, 2, 2]
    @test m.K == [0, 0, 4, 4]

    # Pick alternate producer growth.
    m = default_model(fw, Nutrients.Nodes(3))
    @test !has_component(m, LogisticGrowth)
    @test has_component(m, NutrientIntake)
    @test m.nutrients.number == 3
    @test m.nutrients.turnover == [1 / 4, 1 / 4, 1 / 4]
    @test m.nutrients.concentration == 0.5 .* ones(2, 3)
    @sysfails(
        m.K,
        Property(K, "Component <$CarryingCapacity> is required to read this property.")
    )

    # Explicitly pick the default producer growth.
    m = default_model(fw, LogisticGrowth())
    @test m.M ≈ [31.622776601683793, 10.0, 1.0, 1.0] # BodyMass hook triggered.
    @test m.r == [0, 0, 1, 1]
    @test m.K == [0, 0, 1, 1]

    # Any nutrient component triggers this default.
    m = default_model(fw, Nutrients.Turnover(0.8))
    @test !has_component(m, LogisticGrowth)
    @test has_component(m, NutrientIntake)
    @test m.nutrients.number == m.producers.number == 2
    @test m.nutrients.turnover == [0.8, 0.8]
    @test m.nutrients.concentration == 0.5 .* ones(2, 2)
    @sysfails(
        m.K,
        Property(K, "Component <$CarryingCapacity> is required to read this property.")
    )

    # Tweak directly from inside the aggregated blueprint.
    m = default_model(fw, NutrientIntake(; turnover = 0.8))
    @test !has_component(m, LogisticGrowth)
    @test has_component(m, NutrientIntake)
    @test m.nutrients.number == m.producers.number == 2
    @test m.nutrients.turnover == [0.8, 0.8]
    @test m.nutrients.concentration == 0.5 .* ones(2, 2)
    @sysfails(
        m.K,
        Property(K, "Component <$CarryingCapacity> is required to read this property.")
    )

    # Combine if meaningful.
    m = default_model(fw, Temperature(), NutrientIntake(; turnover = [1, 2]))
    @test m.nutrients.supply == [4, 4]
    @test m.attack_rate[1, 2] == 7.686741690921419e-7

    # Add multiplex layers.
    m = default_model(fw, Competition.Layer(; A = (C = 0.2, sym = true), I = 2))
    NTI = NontrophicInteractions
    @test has_component(m, ClassicResponse) # Auto set.
    @test has_component(m, NTI.Competition.Topology)
    @test has_component(m, NTI.Competition.Intensity)
    @test has_component(m, NTI.Competition.FunctionalForm)
    @test has_component(m, NTI.Competition.Layer)
    @test m.competition.intensity == 2

    # Leverage multiplex API to bring several layers at once.
    m = default_model(
        fw,
        NontrophicLayers(;
            L = (refuge = 4, facilitation = 6),
            intensity = (refuge = 5, facilitation = 8),
        ),
    )
    @test has_component(m, ClassicResponse)
    @test has_component(m, Refuge.Layer)
    @test has_component(m, Facilitation.Layer)
    @test !has_component(m, Competition.Layer)
    @test !has_component(m, Interference.Layer)
    @test m.facilitation.intensity == 8
    @test m.refuge.intensity == 5
    @test sum(m.refuge.links.matrix) == 4
    @test m.facilitation.links.number == 6

    # Check input consistency.
    @argfails(default_model(), "No blueprint specified for a foodweb.")
    @sysfails(
        default_model(fw, BodyMass(2), ClassicResponse(; M = 3)),
        Add(
            InconsistentForSameComponent,
            BodyMass,
            [BodyMass.Flat, false, ClassicResponse.Blueprint],
            [BodyMass.Flat],
        ),
    )
    @argfails(
        default_model(fw, Temperature(290), BioenergeticResponse()),
        "Temperature response is not designed for BioenergeticResponse. \
         Use ClassicResponse instead, or don't specify a temperature."
    )

end

end

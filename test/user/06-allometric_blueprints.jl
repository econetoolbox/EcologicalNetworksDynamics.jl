"""
Test all aspects of typical allometric blueprints,
using producer Growth as an example but without testing anything specific to Growth.
Anything specific to Growth will be tested in a dedicated file.
Anything generic to how aliasing dicts work has already been tested.
However, take this opportunity
"""
module AllometricBlueprintTest

using EcologicalNetworksDynamics

using Test
using EcologicalNetworksDynamics: N, AD
using Main: is_repr, is_disp, @sysfails, Value

@testset "Typical allometric blueprint" begin

    # Defined on the same existing component.
    @test is_disp(
        GrowthRate,
        """
        GrowthRate (component for $(N.Network), expandable from:
          Raw: raw values,
          Map: [producers => growth] map,
          Flat: uniform value,
          Allometric: allometric rates,
          Temperature: allometric rates and activation energy,
        )\
        """,
    )

    bp = GrowthRate.Allometric(:Miele2019)
    @test is_repr(
        bp,
        "<GrowthRate>:Allometric(allometry: Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()))",
    )
    @test is_disp(
        bp,
        """
        blueprint for <GrowthRate>: Allometric {
          allometry: Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()),
        }\
        """,
    )

    # The value inside the blueprint is an aliasing dict.
    @test bp.allometry isa AD.AliasingDict
    @test bp.allometry[:prod][:source_exponent] == bp.allometry[:p][:b] == -0.25
    @test bp.allometry == Allometry(; prod_a = 1, prod_b = -0.25)

    # Build from kwargs.
    @test bp == GrowthRate.Allometric(; p = (; prefactor = 1, source_exponent = -0.25))

    # Expand.
    fw = Foodweb([:a => (:b, :c)])
    M = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, M, mc)
    m = base + bp
    @test m.growth_rate == [0, 1, 1]

    # Allometric parameters are checked against a template.
    @sysfails(
        base + GrowthRate.Allometric(),
        Check(
            early,
            [GrowthRate.Allometric],
            "Missing allometric parameter 'a' (prefactor) for 'producer', \
             required to calculate growth_rates.",
        )
    )
    @sysfails(
        base + GrowthRate.Allometric(; p = (a = 1, b = 2, c = 3)),
        Check(
            early,
            [GrowthRate.Allometric],
            "Allometric parameter 'c' (target_exponent) for 'producer' is meaningless \
             in the context of calculating growth_rates: 3.0.",
        )
    )
    @sysfails(
        base + GrowthRate.Allometric(; p = (a = 1, b = 2), inv_a = 5),
        Check(
            early,
            [GrowthRate.Allometric],
            "Allometric rates for 'invertebrate' are meaningless \
             in the context of calculating growth_rates: (a: 5.0).",
        )
    ) # XXX cannot obtain 'Missing allometric rates' with growth_rate, test with another.

    # Required components.
    @sysfails(Model() + bp, Missing(Foodweb, GrowthRate, [GrowthRate.Allometric], nothing))
    @sysfails(Model(fw) + bp, Missing(BodyMass, nothing, [GrowthRate.Allometric], nothing))
    @sysfails(
        Model(fw, M) + bp,
        Missing(MetabolicClass, nothing, [GrowthRate.Allometric], nothing)
    )

    # XXX: also test with an allometric blueprint bringing *dense* data.
end

@testset "Typical temperature-allometric blueprint" begin

    bp = GrowthRate.Temperature(:Binzer2016)
    @test is_repr(
        bp,
        "<GrowthRate>:Temperature(\
            E_a: -0.84, \
            allometry: Allometry(p: (a: 1.5497531357028967e-7, b: -0.25), i: (), e: ()))",
    )
    @test is_disp(
        bp,
        """
        blueprint for <GrowthRate>: Temperature {
          E_a: -0.84,
          allometry: Allometry(p: (a: 1.5497531357028967e-7, b: -0.25), i: (), e: ()),
        }\
        """,
    )

    @test bp.allometry isa AD.AliasingDict

    # This one also has activation energy.
    @test bp.E_a isa Float64
    @test bp.E_a == -0.84
    @test bp.allometry isa AD.AliasingDict
    a = 1.5497531357028967e-7
    @test bp.allometry[:prod][:prefactor] == bp.allometry[:p][:a] ≈ a
    @test bp ==
          GrowthRate.Temperature(-0.84; p = (; prefactor = a, source_exponent = -0.25))

    # Expand.
    fw = Foodweb([:a => (:b, :c)])
    M = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, M, mc)
    m = base + Temperature() + bp
    @test m.growth_rate == [0, a, a]

    m = base + Temperature(298.5) + bp
    g = 2.812547966878026e-7
    @test m.growth_rate ≈ [0, g, g]

    # Allometric parameters are also checked against a template.
    base += Temperature()
    @sysfails(
        base + GrowthRate.Temperature(-0.84),
        Check(
            early,
            [GrowthRate.Temperature],
            "Missing allometric parameter 'a' (prefactor) for 'producer', \
             required to calculate growth_rates.",
        )
    )
    @sysfails(
        base + GrowthRate.Temperature(-0.84; p = (a = 1, b = 2, c = 3)),
        Check(
            early,
            [GrowthRate.Temperature],
            "Allometric parameter 'c' (target_exponent) for 'producer' is meaningless \
             in the context of calculating growth_rates: 3.0.",
        )
    )
    @sysfails(
        base + GrowthRate.Temperature(-0.84; p = (a = 1, b = 2), inv_a = 5),
        Check(
            early,
            [GrowthRate.Temperature],
            "Allometric rates for 'invertebrate' are meaningless \
             in the context of calculating growth_rates: (a: 5.0).",
        )
    ) # XXX cannot obtain 'Missing allometric rates' with growth_rate, test with another.

    # Required components.
    @sysfails(Model() + bp, Missing(Foodweb, GrowthRate, [GrowthRate.Temperature], nothing))
    @sysfails(Model(fw) + bp, Missing(BodyMass, nothing, [GrowthRate.Temperature], nothing))
    @sysfails(
        Model(fw, M) + bp,
        Missing(MetabolicClass, nothing, [GrowthRate.Temperature], nothing)
    )
    @sysfails(
        Model(fw, M, mc) + bp,
        Missing(Temperature, nothing, [GrowthRate.Temperature], nothing)
    )

    # XXX: also test with an allometric blueprint bringing *dense* data.

end

end

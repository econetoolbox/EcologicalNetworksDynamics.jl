"""
Test all aspects of typical allometric blueprints, using producer growth as an example.
Anything generic to how aliasing dicts work has already been tested.
"""
module AllometricBlueprintTest

# Much inspired by `NodeFieldTest`.

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    N, D, AD, @test_repr, @test_disp, addfails, @bpfails, @checkfails
using Test

const d, _D = D.NodeField(:producers, :growth)

@testset "Nodefield components: allometry blueprint" begin

    # Defined on the same existing component.
    @test_disp(GrowthRate,
        """
        GrowthRate (component for $(N.Network), expandable from:
          Raw: raw values,
          Map: [producers => growth] map,
          Flat: uniform value,
          Allometric: allometric rates,
          Temperature: allometric rates and activation energy,
        )\
        """)

    @test GrowthRate.Allometric <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    # From a symbol or using the 2D kwargs interface.
    bp = GrowthRate.Allometric(:Miele2019)
    @test bp == GrowthRate(:Miele2019)
    @test bp == GrowthRate.Allometric(; prod_a = 1, prod_b = -0.25)
    @test bp == GrowthRate.Allometric(; p = (; prefactor = 1, source_exponent = -0.25))

    # The value inside the blueprint is an aliasing dict.
    @test bp.allometry isa Allometry
    @test bp.allometry == Allometry(; prod_a = 1, prod_b = -0.25)
    @test bp.allometry[:prod][:source_exponent] == bp.allometry[:p][:b] == -0.25

    @test_repr(bp,
        "<GrowthRate>:Allometric(allometry: \
                                 Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()))")
    @test_disp(bp,
        """
        blueprint for <GrowthRate>: Allometric {
          allometry: Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()),
        }\
        """)

    @bpfails(GrowthRate.Allometric(5),
        GrowthRate.Allometric, :construct,
        (d, 5, :uwhole, "Cannot convert to `Allometry`:\nConversion not implemented."))
    @bpfails(GrowthRate.Allometric(:nap),
        GrowthRate.Allometric, :construct,
        (d, :nap, :uwhole, "Expected one of [:Miele2019]."))
    @checkfails(GrowthRate(:nap),
        d, :nap, :uwhole, "Expected one of [:Miele2019 or :Binzer2016].")

    #---------------------------------------------------------------------------------------
    # Early check.

    fw = Foodweb([:a => (:b, :c)])
    M = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, M, mc)

    for (invalid, mess) in [
        ((;),
            "Missing allometric parameter a (prefactor) for producer, \
            required to calculate growth_rates."),
        ((; p = (a = 1, b = 2, c = 3)),
            "Allometric parameter c (target_exponent) for producer is meaningless \
             in the context of calculating growth_rates: 3.0."),
        ((; p = (a = 1, b = 2), inv_a = 5),
            "Allometric rates for invertebrate are meaningless \
             in the context of calculating growth_rates: (a: 5.0)."),
    ]
        # On construction.
        @bpfails(GrowthRate.Allometric(; invalid...),
            GrowthRate.Allometric, :construct,
            (d, invalid, :uwhole, mess))
        # On expansion.
        bp.allometry = Allometry(; invalid...)
        addfails.@check(base + bp, [],
            (GrowthRate.Allometric, :early, (d, invalid, :uwhole, mess)))
    end
    # XXX cannot obtain 'Missing allometric rates' with growth_rate, test with another.

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = GrowthRate(:Miele2019)
    m = base + bp
    @test m.growth_rate == [1, 1]

    # Required components.
    addfails.@missing(Model() + bp,
        Foodweb, GrowthRate, [GrowthRate.Allometric], nothing)
    addfails.@missing(Model(fw) + bp,
        BodyMass, nothing, [GrowthRate.Allometric], nothing)
    addfails.@missing(Model(fw, M) + bp,
        MetabolicClass, nothing, [GrowthRate.Allometric], nothing)

end

@testset "Nodefield components: temperature-allometry blueprint" begin

    # Much inspired from the above.

    @test GrowthRate.Temperature <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    a = exp(-15.68)

    bp = GrowthRate.Temperature(:Binzer2016)
    @test bp == GrowthRate(:Binzer2016)
    @test bp == GrowthRate.Temperature(-0.84; p = (; a, b = -0.25))

    @test bp.E_a isa Float64
    @test bp.allometry isa Allometry
    @test bp.allometry == Allometry(; prod_a = a, prod_b = -0.25)

    @test_repr(bp,
        "<GrowthRate>:Temperature(E_a: -0.84, allometry: \
                                  Allometry(p: (a: $a, b: -0.25), i: (), e: ()))")
    @test_disp(bp,
        """
        blueprint for <GrowthRate>: Temperature {
          E_a: -0.84,
          allometry: Allometry(p: (a: $a, b: -0.25), i: (), e: ()),
        }\
        """)

    @bpfails(GrowthRate.Temperature(5im),
        GrowthRate.Temperature, :construct,
        (d, 5im, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))
    @bpfails(GrowthRate.Temperature(:nap),
        GrowthRate.Temperature, :construct,
        (d, :nap, :uwhole, "Expected one of [:Binzer2016]."))

    #---------------------------------------------------------------------------------------
    # Early check.

    fw = Foodweb([:a => (:b, :c)])
    bm = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, bm, mc)

    E_a = -0.84
    for (invalid, mess) in [
        ((;),
            "Missing allometric parameter a (prefactor) for producer, \
             required to calculate growth_rates."),
        ((; p = (a = 1, b = 2, c = 3)),
            "Allometric parameter c (target_exponent) for producer is meaningless \
             in the context of calculating growth_rates: 3.0."),
        ((; p = (a = 1, b = 2), inv_a = 5),
            "Allometric rates for invertebrate are meaningless \
             in the context of calculating growth_rates: (a: 5.0)."),
    ]
        @bpfails(GrowthRate.Temperature(E_a; invalid...),
            GrowthRate.Temperature, :construct, (d, invalid, :uwhole, mess))
        bp.allometry = Allometry(; invalid...)
        addfails.@check(base + Temperature() + bp, [],
            (GrowthRate.Temperature, :early, (d, invalid, :uwhole, mess)))
    end
    # XXX cannot obtain 'Missing allometric rates' with growth_rate, test with another.

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = GrowthRate(:Binzer2016)
    m = base + Temperature() + bp
    @test m.growth_rate ≈ [a, a]

    m = base + Temperature(298.5) + bp
    g = 2.812547966878026e-7
    @test m.growth_rate ≈ [g, g]

    # Required components.
    addfails.@missing(Model() + bp, Foodweb, GrowthRate, [GrowthRate.Temperature], nothing)
    addfails.@missing(Model(fw) + bp, BodyMass, nothing, [GrowthRate.Temperature], nothing)
    addfails.@missing(Model(fw, bm) + bp,
        MetabolicClass, nothing, [GrowthRate.Temperature], nothing)
    addfails.@missing(Model(fw, bm, mc) + bp,
        Temperature, nothing, [GrowthRate.Temperature], nothing)

    # XXX: also test with an allometric blueprint bringing *dense* data.

end

end

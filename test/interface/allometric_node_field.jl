"""
Test all aspects of typical allometric blueprints for a node field,
using producer growth as an example.
Anything generic to how aliasing dicts work has already been tested.
"""
module AllometricBlueprintNodeFieldTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    ST, SL, AD, @test_repr, @test_disp, addfails, @bpfails, @checkfails
using Test

const s, S = SL.NodeField(:producers, :growth)

@testset "Allometry blueprint: nodefield." begin

    # Defined on the same existing component.
    @test_disp(Growth,
        """
        Growth (component for $(ST.Network), expandable from:
          Raw: raw values,
          Map: [producers => growth] map,
          Flat: uniform value,
          Allometric: allometric rates,
          Temperature: allometric rates and activation energy,
        )\
        """)

    @test Growth.Allometric <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    # From a symbol or using the 2D kwargs interface.
    bp = Growth.Allometric(:Miele2019)
    @test bp == Growth(:Miele2019)
    @test bp == Growth.Allometric(; prod_a = 1, prod_b = -0.25)
    @test bp == Growth.Allometric(; p = (; prefactor = 1, source_exponent = -0.25))

    # The value inside the blueprint is an aliasing dict.
    @test bp.allometry isa Allometry
    @test bp.allometry == Allometry(; prod_a = 1, prod_b = -0.25)
    @test bp.allometry[:prod][:source_exponent] == bp.allometry[:p][:b] == -0.25

    @test_repr(bp,
        "<Growth>:Allometric(allometry: \
                             Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()))")
    @test_disp(bp,
        """
        blueprint for <Growth>: Allometric {
          allometry: Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()),
        }\
        """)

    @bpfails(Growth.Allometric(5),
        Growth.Allometric, :construct,
        (s, 5, :uwhole, "Cannot convert to `Allometry`:\nConversion not implemented."))
    @bpfails(Growth.Allometric(:nap),
        Growth.Allometric, :construct,
        (s, :nap, :uwhole, "Expected one of [:Miele2019]."))
    @checkfails(Growth(:nap),
        s, :nap, :uwhole, "Expected one of [:Miele2019 or :Binzer2016].")

    #---------------------------------------------------------------------------------------
    # Early check.

    fw = Foodweb([:a => (:b, :c)])
    M = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, M, mc)

    for (invalid, mess) in [
        ((;),
            "Missing allometric rates for metabolic class producer, \
             required to calculate growth."),
        ((; p_a = 1),
            "Missing allometric parameter b (source_exponent) for producer, \
             required to calculate growth."),
        ((; p = (a = 1, b = 2, c = 3)),
            "Allometric parameter c (target_exponent) for producer is meaningless \
             in the context of calculating growth: 3.0."),
        ((; p = (a = 1, b = 2), inv_a = 5),
            "Allometric rates for invertebrate are meaningless \
             in the context of calculating growth: (a: 5.0)."),
    ]
        # On construction.
        @bpfails(Growth.Allometric(; invalid...),
            Growth.Allometric, :construct,
            (s, invalid, :uwhole, mess))
        # On expansion.
        bp.allometry = Allometry(; invalid...)
        addfails.@check(base + bp, [],
            (Growth.Allometric, :early, (s, invalid, :uwhole, mess)))
    end

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = Growth(:Miele2019)
    m = base + bp
    @test m.r == [1, 1]

    # Required components.
    addfails.@missing(Model() + bp, Foodweb, Growth, [Growth.Allometric], nothing)
    addfails.@missing(Model(fw) + bp, BodyMass, nothing, [Growth.Allometric], nothing)
    addfails.@missing(Model(fw, M) + bp,
        MetabolicClass, nothing, [Growth.Allometric], nothing)

end

@testset "Temperature-allometry blueprints: nodefield." begin

    # Much inspired from the above.

    @test Growth.Temperature <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    a = exp(-15.68)

    bp = Growth.Temperature(:Binzer2016)
    @test bp == Growth(:Binzer2016)
    @test bp == Growth.Temperature(-0.84; p = (; a, b = -0.25))

    @test bp.E_a isa Float64
    @test bp.allometry isa Allometry
    @test bp.allometry == Allometry(; prod_a = a, prod_b = -0.25)

    @test_repr(bp,
        "<Growth>:Temperature(E_a: -0.84, allometry: \
                                          Allometry(p: (a: $a, b: -0.25), i: (), e: ()))")
    @test_disp(bp,
        """
        blueprint for <Growth>: Temperature {
          E_a: -0.84,
          allometry: Allometry(p: (a: $a, b: -0.25), i: (), e: ()),
        }\
        """)

    @bpfails(Growth.Temperature(5im),
        Growth.Temperature, :construct,
        (s, 5im, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))
    @bpfails(Growth.Temperature(:nap),
        Growth.Temperature, :construct,
        (s, :nap, :uwhole, "Expected one of [:Binzer2016]."))

    #---------------------------------------------------------------------------------------
    # Early check.

    fw = Foodweb([:a => (:b, :c)])
    bm = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    base = Model(fw, bm, mc)

    E_a = -0.84
    for (invalid, mess) in [
        ((;),
            "Missing allometric rates for metabolic class producer, \
             required to calculate growth."),
        ((; p_a = 1),
            "Missing allometric parameter b (source_exponent) for producer, \
             required to calculate growth."),
        ((; p = (a = 1, b = 2, c = 3)),
            "Allometric parameter c (target_exponent) for producer is meaningless \
             in the context of calculating growth: 3.0."),
        ((; p = (a = 1, b = 2), inv_a = 5),
            "Allometric rates for invertebrate are meaningless \
             in the context of calculating growth: (a: 5.0)."),
    ]
        @bpfails(Growth.Temperature(E_a; invalid...),
            Growth.Temperature, :construct, (s, invalid, :uwhole, mess))
        bp.allometry = Allometry(; invalid...)
        addfails.@check(base + Temperature() + bp, [],
            (Growth.Temperature, :early, (s, invalid, :uwhole, mess)))
    end

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = Growth(:Binzer2016)
    m = base + Temperature() + bp
    @test m.r ≈ [a, a]

    m = base + Temperature(298.5) + bp
    g = 2.812547966878026e-7
    @test m.r ≈ [g, g]

    # Required components.
    addfails.@missing(Model() + bp, Foodweb, Growth, [Growth.Temperature], nothing)
    addfails.@missing(Model(fw) + bp, BodyMass, nothing, [Growth.Temperature], nothing)
    addfails.@missing(Model(fw, bm) + bp,
        MetabolicClass, nothing, [Growth.Temperature], nothing)
    addfails.@missing(Model(fw, bm, mc) + bp,
        Temperature, nothing, [Growth.Temperature], nothing)

end

end

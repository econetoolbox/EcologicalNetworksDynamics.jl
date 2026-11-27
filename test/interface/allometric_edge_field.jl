"""
Test all aspects of typical allometric blueprints for an edge field,
using handling time as an example.
"""
module AllometricBlueprintEdgeFieldTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    ST, SL, AD, @test_repr, @test_disp, addfails, @bpfails, @checkfails
using Test

const s, S = SL.EdgeField(:trophic, :handling_time)

# XXX: not tested with base (non-temperature) allometry yet.
# Do it as soon as such a component shows up.

@testset "Temperature-allometry blueprint: edgefield." begin

    # Defined on the same existing component.
    @test_disp(HandlingTime,
        """
        HandlingTime (component for $(ST.Network), expandable from:
          Raw: raw values,
          Matrix: a sparse matrix,
          Adjacency: [species => [species => handling_time]] adjacency list,
          Flat: uniform value,
          Miele2019: body masses,
          Temperature: allometric rates and activation energy,
        )\
        """)

    @test HandlingTime.Temperature <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    a = exp(9.66)

    bp = HandlingTime.Temperature(:Binzer2016)
    @test bp == HandlingTime(:Binzer2016)
    @test bp == HandlingTime.Temperature(0.26;
        p = (; a = 0, b = -0.45, c = 0.47),
        i = (; a, b = -0.45, c = 0.47),
        e = (; a, b = -0.45, c = 0.47),
    )

    @test bp.E_a isa Float64
    @test bp.allometry isa Allometry

    @bpfails(HandlingTime.Temperature(5im),
        HandlingTime.Temperature, :construct,
        (s, 5im, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))
    @bpfails(HandlingTime.Temperature(:nap),
        HandlingTime.Temperature, :construct,
        (s, :nap, :uwhole, "Expected one of [:Binzer2016]."))

    #---------------------------------------------------------------------------------------
    # Early check.

    fw = Foodweb([:a => [:b, :c], :b => :c])
    bm = BodyMass(; Z = 1)
    mc = MetabolicClass(:all_invertebrates)
    tp = Temperature()
    base = Model(fw, bm, mc, tp)

    E_a = 0.26
    for (invalid, mess) in [
        ((;),
            "Missing allometric rates for metabolic class producer, \
             required to calculate handling_times."),
        ((; p_a = 1, p_c = 3),
            "Missing allometric parameter b (source_exponent) for producer, \
             required to calculate handling_times."),
    ]
        @bpfails(HandlingTime.Temperature(E_a; invalid...),
            HandlingTime.Temperature, :construct, (s, invalid, :uwhole, mess))
        bp.allometry = Allometry(; invalid...)
        addfails.@check(base + bp, [],
            (HandlingTime.Temperature, :early, (s, invalid, :uwhole, mess)))
    end

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = HandlingTime(:Binzer2016)
    m = base + bp
    @test m.trophic.handling_time ≈ [
        0 a a
        0 0 a
        0 0 0
    ]

    # Required components.
    addfails.@missing(Model() + bp,
        Foodweb, HandlingTime, [HandlingTime.Temperature], nothing)
    addfails.@missing(Model(fw) + bp,
        BodyMass, nothing, [HandlingTime.Temperature], nothing)
    addfails.@missing(Model(fw, bm) + bp,
        MetabolicClass, nothing, [HandlingTime.Temperature], nothing)
    addfails.@missing(Model(fw, bm, mc) + bp,
        Temperature, nothing, [HandlingTime.Temperature], nothing)

end

end

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
using Main: is_repr, is_disp

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

    bp = GrowthRate.Allometric(:Miele2016)
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

    base = Model(
        Foodweb([:a => (:b, :c)]),
        BodyMass(; Z = 1),
        MetabolicClass(:all_invertebrates),
    )

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


end

end

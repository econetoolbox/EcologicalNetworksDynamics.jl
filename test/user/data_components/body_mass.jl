module BodyMassTest

using EcologicalNetworksDynamics

using Test
using EcologicalNetworksDynamics: Network
using Main: is_disp, is_repr, @argfails, @sysfails, Value

@testset "Body mass component." begin

    # Bodymass is a regular node field component.
    m = Model(BodyMass([1, 2, 3]))

    # Legacy alias.
    @test m.body_mass === m.M
    @test BodyMass(; M = [4, 5, 6]) == BodyMass.Raw([4, 5, 6])
    @test BodyMass(; M = 2) == BodyMass.Flat(2)

    # It also has a special way of being built from trophic levels.
    bp = BodyMass.Z(2.8)
    @test bp == BodyMass(; Z = 2.8)
    @test is_repr(bp, "<BodyMass>:Z(Z: 2.8)")
    @test is_disp(
        bp,
        """
        blueprint for <BodyMass>: Z {
          Z: 2.8,
        }\
        """,
    )
    # This one requires a foodweb because it is built from trophic levels.
    fw = Foodweb([:a => [:b, :c], :b => :c])
    m = Model(fw, bp)
    @test m.trophic.level == [2.5, 2, 1]
    @test m.body_mass == [2.8^1.5, 2.8, 1]

    # Expansion failures.
    @sysfails(Model(bp), Missing(Foodweb, nothing, [BodyMass.Z], nothing))
    @sysfails(Model(Species(3), bp), Missing(Foodweb, nothing, [BodyMass.Z], nothing))
    @sysfails(
        Model(fw, BodyMass(; Z = -1)),
        Check(
            early,
            [BodyMass.Z],
            "Cannot calculate body masses from trophic levels \
             with a negative value of Z.\n\
             Received: -1.0",
        )
    )

    # Input guards.
    @argfails(BodyMass(), "Either 'M' or 'Z' must be provided to define body masses.")
    @argfails(BodyMass([1, 2], Z = 3.4), "Unexpected argument: Z = 3.4.")
    @argfails(
        BodyMass(M = [1, 2], Z = 3.4),
        "Cannot specify both 'M' and 'Z' to define body masses."
    )

end

end

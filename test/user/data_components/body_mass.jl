module BodyMassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    D, N, @test_disp, @test_repr, addfails, @test_err, @bpfails, @argfails
using Test

const d, _D = D.NodeField(:species, :body_mass)

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
    @test_repr(bp, "<BodyMass>:Z(Z: 2.8)")
    @test_disp(bp,
        """
        blueprint for <BodyMass>: Z {
          Z: 2.8,
        }\
        """)

    # This one requires a foodweb because it is built from trophic levels.
    fw = Foodweb([:a => [:b, :c], :b => :c])
    m = Model(fw, bp)
    @test m.trophic.level == [2.5, 2, 1]
    @test m.body_mass == [2.8^1.5, 2.8, 1]

    # Expansion failures.
    noneg = "Cannot calculate body masses from trophic levels with a negative value of Z."
    @bpfails(Model(fw, BodyMass(; Z = -1)),
        BodyMass.Z, :construct, (d, -1.0, :whole, nothing, noneg))
    bp.Z *= -1
    addfails.@check(Model(fw, bp), [],
        (BodyMass.Z, :early, (d, -2.8, :whole, nothing, noneg)))
    addfails.@missingrequired(Model(bp), Species, BodyMass, [BodyMass.Z], nothing)
    addfails.@missingrequired(
        Model(Species(3), bp),
        Foodweb,
        nothing,
        [BodyMass.Z],
        nothing
    )

    # Input guards.
    @argfails(BodyMass(), "Either 'M' or 'Z' must be provided to define body masses.")
    @test_err(BodyMass([1, 2], Z = 3.4),
        """
        Unexpected keyword arguments to blueprint constructor:
        in BodyMass.Raw:
        Received: pairs(::$NamedTuple) with 1 entry:
          :Z => 3.4
        Type: $Base.Pairs{$Symbol, $Float64, $Nothing, @NamedTuple{Z::$Float64}}\
        """
    )
    @argfails(
        BodyMass(M = [1, 2], Z = 3.4),
        "Cannot specify both 'M' and 'Z' to define body masses."
    )

end

end

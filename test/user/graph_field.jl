"""
Test a typical GraphScalar component, using Temperature as an example,
but without testing anything specific to temperature.
(anything specific to temperature will be tested in a dedicated file)
"""
module GraphField

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    N, F, @test_repr, @test_disp, @bpfails, addfails
using Test

@testset "Typical GraphScalar component" begin

    # Only one blueprint yet.
    @test Temperature isa Component
    @test_repr(Temperature, "Temperature")
    @test_disp(
        Temperature,
        """
        Temperature (component for $(N.Network), expandable from:
          Raw: raw temperature value,
        )\
        """,
    )
    @test Temperature.Raw <: Blueprint

    # Construct from raw values, regardless of input type.
    bp = Temperature.Raw(215.0)
    @test bp == Temperature.Raw(215)
    @test bp == Temperature(215) # Component as constructor.

    # Checked on construction.
    @bpfails(Temperature(-1), Temperature.Raw, :construct, nothing,
        (nothing, nothing, :check, -1.0, "Value cannot be negative."))

    # Expand into a field component.
    m = Model(bp)
    @test_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 1 component:
          - Temperature: 215.0\
        """,
    )

    # The value becomes directly available.
    @test m.temperature isa Float64
    @test m.temperature == 215
    @test m.T == 215 # Short name alias.

    # The value is immutable, but it can be reassigned
    # with correct COW handling.
    mt = m.T
    alt = copy(m)
    at = alt.T
    @test mt == at == 215
    m.T = 244
    @test mt == at == alt.T == 215 # Old values unchanged (not views)
    @test m.T == 244 # Current model updated.

    # Value is still checked.
    @bpfails(m.T = -1, -1.0, "Value cannot be negative.")
    bp.T = -1 # Even after blueprint corruption.
    addfails.@check(
        Model(bp),
        [Temperature.Raw],
        """
        When checking <temperature> blueprint data:
        Value cannot be negative.
        Received: -1.0 ::$Float64\
        """,
        false,
    )

end

end

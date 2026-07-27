"""
Test all aspects of typical GraphScalar component,
using Temperature as an example, but without testing anything specific to temperature.
Anything specific to temperature will be tested in a dedicated file.
"""
module GraphScalarTest

using EcologicalNetworksDynamics

using Test
using EcologicalNetworksDynamics: EN, N, F
using Main: is_repr, is_disp, @inputfails, @sysfails, Value

@testset "Typical GraphScalar component" begin

    # Only one blueprint yet.
    @test Temperature isa EN.Component
    @test is_repr(Temperature, "Temperature")
    @test is_disp(
        Temperature,
        """
        Temperature (component for $(N.Network), expandable from:
          Raw: raw temperature value,
        )\
        """,
    )
    @test Temperature.Raw <: EN.Blueprint

    # Construct from raw values, regardless of input type.
    bp = Temperature.Raw(215.0)
    @test bp == Temperature.Raw(215)
    @test bp == Temperature(215) # Component as constructor.

    # Checked on construction.
    nonneg = "Value cannot be negative."
    @inputfails(Temperature(-1), nonneg, -1)

    # Expand into a field component.
    m = Model(bp)
    @test is_disp(
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
    @inputfails(m.T = -1, nonneg, -1)
    bp.T = -1 # Even after blueprint corruption.
    @sysfails(
        Model(bp),
        Check(
            early,
            [Temperature.Raw],
            "When checking raw value for <temperature>:\n$nonneg\nReceived: -1.0",
        )
    )

end

end

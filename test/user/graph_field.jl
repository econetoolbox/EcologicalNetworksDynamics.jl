"""
Test a typical GraphScalar component, using Temperature as an example,
but without testing anything specific to temperature.
(anything specific to temperature will be tested in a dedicated file)
"""
module GraphField

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    EN, N, D, F, @jl_basic_callfails, @test_repr, @test_disp, @test_err, @bpfails,
    @mutfails,
    addfails
using Test

const d, _D = D.GraphField(:temperature)

@testset "Typical GraphScalar component" begin

    # Blueprints available from the component.
    @test Temperature isa Component

    # These representations used to be fancy, leading to confusing errors and reports.
    # Avoid piracy and use default display instead.
    @test_repr(typeof(Temperature), "$EN._Temperature")
    @test_repr(Temperature, "$EN._Temperature($EN.Temperature_.Raw)")

    # These ones may be fancy.
    @test_disp(typeof(Temperature), "<Temperature> (component type for $(N.Network))")
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
    @test bp.T isa Float64
    @test bp == Temperature.Raw(215)
    @test bp == Temperature(215) # Component as constructor.

    # Checked on construction.
    @jl_basic_callfails(Temperature(5, 8))
    @jl_basic_callfails(Temperature(5; a = 8))
    @bpfails(Temperature(-1),
        Temperature.Raw, :construct, (d, -1.0, :uwhole, "Value cannot be negative."))
    @test_err(Temperature(-1), # First time we test with @bpfails: check the actual report.
        """
        While constructing blueprint Temperature.Raw:
        In the provided input for <temperature>:
        Value cannot be negative.
        Received: -1.0  ::Float64\
        """
    )
    @bpfails(Temperature(:a),
        Temperature.Raw, :construct,
        (d, :a, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))

    # Expand into a field component.
    m = Model(bp)
    @test has_component(m, Temperature)
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
    @mutfails(m.T = -1, (d, -1.0, :uwhole, "Value cannot be negative."))
    @test_err(m.T = -1, # First time with @mutfails.
        """
        While mutating model:
        In the provided input for <temperature>:
        Value cannot be negative.
        Received: -1.0  ::Float64\
        """
    )

    bp.T = -1 # Even after blueprint corruption.
    addfails.@check(Model(bp), [],
        (Temperature.Raw, :early, (d, -1.0, :uwhole, "Value cannot be negative.")))
    @test_err(Model(bp), # First time nested within @check.
        """
        Blueprint value cannot be expanded:
        While verifying blueprint:
        In the provided input for <temperature>:
        Value cannot be negative.
        Received: -1.0  ::Float64
        in Temperature.Raw\
        """
    )

end

end

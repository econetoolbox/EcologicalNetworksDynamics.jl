module TemperatureTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: D, @convfails, @bpfails
using Test

const d, _D = D.GraphField(:temperature)

@testset "Temperature component." begin

    # Only test default, value,
    # all the rest having been tested in the context of generic GraphScalar components.
    bp = Temperature()
    @test bp == Temperature.Raw(293.15)

    # Use Celcius degrees.
    @test bp == Temperature(; celc = 20)

    # Although don't mess around.
    @convfails(Temperature(; celc = :x),
        Float64, :x, :uwhole, "Conversion not implemented.")
    @bpfails(Temperature(; celc = -8000),
        Temperature.Raw, :construct, (d, -7726.85, :uwhole, "Value cannot be negative."))

end

end

module TemperatureTest

using EcologicalNetworksDynamics

using Test

@testset "Temperature component." begin

    # Only test default, value,
    # all the rest having been tested in the context of generic GraphScalar components.
    bp = Temperature()
    @test bp == Temperature.Raw(293.15)

end

end

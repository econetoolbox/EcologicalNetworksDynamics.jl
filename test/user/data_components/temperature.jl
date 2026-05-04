module TemperatureTest

using EcologicalNetworksDynamics

using Test

@testset "Temperature component." begin

    # Default value.
    bp = Temperature()
    @test bp == Temperature.Raw(293.15)

end

end

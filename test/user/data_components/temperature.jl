module TestTemperature
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Temperature component." begin

    m = Model(Temperature())
    @test m.temperature == m.T == 293.15

    m = Model(Temperature(200))
    @test m.temperature == m.T == 200.0

    # Editable.
    m.temperature = 250
    @test m.temperature == m.T == 250.0

    mess = "Not a positive (Kelvin) value: T ="
    @sysfails(Model(Temperature(-4)), Check(early, [Temperature.Raw], "$mess -4.0."))

    @failswith((m.T = -1), WriteError("$mess -1.", :temperature, nothing, -1))

end

end

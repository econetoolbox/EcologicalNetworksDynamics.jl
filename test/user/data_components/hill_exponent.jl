module TestHillExponent
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Hill exponent component." begin

    m = Model(HillExponent(2))
    @test m.hill_exponent == m.h == 2

    m.h = 3
    @test m.hill_exponent == m.h == 3

    mess = "Not a positive (power) value: h ="
    @sysfails(Model(HillExponent(-4)), Check(early, [HillExponent.Raw], "$mess -4.0."))
    @failswith(m.h = -1, WriteError("$mess -1.", :hill_exponent, nothing, -1))

end

end

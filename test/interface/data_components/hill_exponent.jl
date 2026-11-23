module HillExponentTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @bpfails
using Test

const s, S = SL.GraphField(:hill_exponent)

@testset "HillExponent." begin

    @test HillExponent isa Component

    m = Model(HillExponent())
    @test m.hill_exponent isa Float64
    @test m.hill_exponent == m.h == 2

    @bpfails(HillExponent(-1),
        HillExponent.Raw, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

end

end

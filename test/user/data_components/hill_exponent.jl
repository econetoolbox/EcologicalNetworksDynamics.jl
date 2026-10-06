module HillExponentTest

using EcologicalNetworksDynamics

using Test
using Main: @inputfails, @sysfails, Value

@testset "HillExponent component." begin

    # Checked conversion to a positive Float64.
    bp = HillExponent(2)
    @test bp.h isa Float64
    @test bp.h == 2
    m = Model(bp)
    @test m.h isa Float64
    m.h = 3
    @test m.h isa Float64
    @test m.h == 3
    @inputfails(m.h = -1, "Value cannot be negative.", -1)

end

end

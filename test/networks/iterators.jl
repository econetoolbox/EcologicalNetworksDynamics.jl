module Iterators

using EcologicalNetworksDynamics: N

using Test

@testset "Iteration utils" begin

    @test collect(N.stopwhen(>=(30), [10, 20, 30, 40])) == [10, 20]

    @test collect(N.filter_map(1:5) do i
        i % 2 == 0 ? Some(i) : nothing
    end) == [2, 4]

end

end

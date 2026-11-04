module SharedUtilsTests

using EcologicalNetworksDynamics: stopwhen, filter_map, zip_longest

using Test

@testset "Iteration utils" begin

    @test collect(stopwhen(>=(30), [10, 20, 30, 40])) == [10, 20]

    @test collect(filter_map(1:5) do i
        i % 2 == 0 ? Some(i) : nothing
    end) == [2, 4]

    @test collect(zip_longest(1:3, (1:8) * 10, (1:5) * 100)) == [
        (1, 10, 100),
        (2, 20, 200),
        (3, 30, 300),
        (nothing, 40, 400),
        (nothing, 50, 500),
        (nothing, 60, nothing),
        (nothing, 70, nothing),
        (nothing, 80, nothing),
    ]

end

end

module TestEnvironment
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "Environment" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 0 1 0])
    environment = Environment() # Default.
    @test environment.T == 293.15
    environment = Environment(; T = 300) # Custom temperature.
    @test environment.T == 300
end

end

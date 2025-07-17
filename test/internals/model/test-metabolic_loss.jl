module MetabolicLoss
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "Metabolic loss" begin
    foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0])
    p = ModelParameters(foodweb)
    B = [1, 1, 1]
    @test Internals.metabolic_loss(1, B, p) == 0 # no loss for producers
    @test Internals.metabolic_loss(2, B, p) == 0 # no loss for producers
    @test Internals.metabolic_loss(3, B, p) == 0.314 # loss for consumers...
    B = [2, 2, 2]
    @test Internals.metabolic_loss(3, B, p) == 2 * 0.314 # ...increase with biomass
end

end

module Consumption
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "Consumption: bioenergetic" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0])

    # Bioenergetic - default
    p = ModelParameters(foodweb)
    B = [1.0, 1, 1]
    fᵣmatrix = p.functional_response(B)
    eating1, being_eaten1 = Internals.consumption(1, B, p, fᵣmatrix)
    eating2, being_eaten2 = Internals.consumption(2, B, p, fᵣmatrix)
    eating3, being_eaten3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eating1 ≈ 0 atol = 1e-5 # species 1 does not eat
    @test (eating2 > 0) & (eating3 > 0) # species 2 & 3 eat
    @test being_eaten3 ≈ 0 atol = 1e-5 # species 3 is not eaten
    @test being_eaten1 > being_eaten2 > 0 # species 1 & 2 are eaten
    B₂ = [2.0, 1, 1] # increasing producer biomass...
    fᵣmatrix₂ = p.functional_response(B₂)
    eating₂1, being_eaten₂1 = Internals.consumption(1, B₂, p, fᵣmatrix₂)
    eating₂2, being_eaten₂2 = Internals.consumption(2, B₂, p, fᵣmatrix₂)
    eating₂3, being_eaten₂3 = Internals.consumption(3, B₂, p, fᵣmatrix₂)
    @test eating₂2 > eating₂3 #... benefits more to the species feeding only on producer
    @test being_eaten₂1 > being_eaten1 #... and more producer biomass is consumed

    # Bioenergetic with intraspecific interference
    F = BioenergeticResponse(foodweb; c = [0, 0, 0.5]) # intra interference for species 3
    p = ModelParameters(foodweb; functional_response = F)
    fᵣmatrix = p.functional_response(B)
    eatingᵢ1, being_eatenᵢ1 = Internals.consumption(1, B, p, fᵣmatrix)
    eatingᵢ2, being_eatenᵢ2 = Internals.consumption(2, B, p, fᵣmatrix)
    eatingᵢ3, being_eatenᵢ3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eatingᵢ1 ≈ 0 atol = 1e-5
    @test being_eatenᵢ3 ≈ 0 atol = 1e-5
    @test eatingᵢ2 ≈ eating2 atol = 1e-5 # no change for species 2
    @test eatingᵢ3 < eating3 # decrease of species 3 consumption
end

@testset "Consumption: classic (foodweb)" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0])

    # Classic default
    p = ModelParameters(foodweb; functional_response = ClassicResponse(foodweb; aᵣ = 0.5))
    B = [1.0, 1, 1]
    fᵣmatrix = p.functional_response(B, foodweb)
    eating1, being_eaten1 = Internals.consumption(1, B, p, fᵣmatrix)
    eating2, being_eaten2 = Internals.consumption(2, B, p, fᵣmatrix)
    eating3, being_eaten3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eating1 ≈ 0 atol = 1e-5 # species 1 does not eat
    @test (eating2 > 0) & (eating3 > 0) # species 2 & 3 eat
    @test being_eaten3 ≈ 0 atol = 1e-5 # species 3 is not eaten
    @test being_eaten1 > being_eaten2 > 0 # species 1 & 2 are eaten
    B₂ = [2.0, 1, 1] # increasing producer biomass...
    fᵣmatrix₂ = p.functional_response(B₂, foodweb)
    eating₂1, being_eaten₂1 = Internals.consumption(1, B₂, p, fᵣmatrix₂)
    eating₂2, being_eaten₂2 = Internals.consumption(2, B₂, p, fᵣmatrix₂)
    eating₂3, being_eaten₂3 = Internals.consumption(3, B₂, p, fᵣmatrix₂)
    @test eating₂2 > eating₂3 #... benefits more to the species feeding only on producer
    @test being_eaten₂1 > being_eaten1 #... and more producer biomass is consumed

    # Classic with intraspecific interference
    F = ClassicResponse(foodweb; c = [0, 0, 0.5], aᵣ = 0.5) # intra interference for species 3
    p = ModelParameters(foodweb; functional_response = F)
    fᵣmatrix = p.functional_response(B, foodweb)
    eatingᵢ1, being_eatenᵢ1 = Internals.consumption(1, B, p, fᵣmatrix)
    eatingᵢ2, being_eatenᵢ2 = Internals.consumption(2, B, p, fᵣmatrix)
    eatingᵢ3, being_eatenᵢ3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eatingᵢ1 ≈ 0 atol = 1e-5
    @test being_eatenᵢ3 ≈ 0 atol = 1e-5
    @test eatingᵢ2 ≈ eating2 atol = 1e-5 # no change for species 2
    @test eatingᵢ3 < eating3 # decrease of species 3 consumption
end

@testset "Consumption: classic (multiplex network)" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0])

    # Classic default (no non-trophic interactions)
    multiplex_network = MultiplexNetwork(foodweb) # by default no non-trophic interactions
    response = ClassicResponse(multiplex_network; aᵣ = 0.5)
    p = ModelParameters(multiplex_network; functional_response = response)
    B = [1.0, 1, 1]
    fᵣmatrix = p.functional_response(B, multiplex_network)
    eating1, being_eaten1 = Internals.consumption(1, B, p, fᵣmatrix)
    eating2, being_eaten2 = Internals.consumption(2, B, p, fᵣmatrix)
    eating3, being_eaten3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eating1 ≈ 0 atol = 1e-5 # species 1 does not eat
    @test (eating2 > 0) & (eating3 > 0) # species 2 & 3 eat
    @test being_eaten3 ≈ 0 atol = 1e-5 # species 3 is not eaten
    @test being_eaten1 > being_eaten2 > 0 # species 1 & 2 are eaten
    B₂ = [2.0, 1, 1] # increasing producer biomass...
    fᵣmatrix₂ = p.functional_response(B₂, multiplex_network)
    eating₂1, being_eaten₂1 = Internals.consumption(1, B₂, p, fᵣmatrix₂)
    eating₂2, being_eaten₂2 = Internals.consumption(2, B₂, p, fᵣmatrix₂)
    eating₂3, being_eaten₂3 = Internals.consumption(3, B₂, p, fᵣmatrix₂)
    @test eating₂2 > eating₂3 #... benefits more to the species feeding only on producer
    @test being_eaten₂1 > being_eaten1 #... and more producer biomass is consumed

    # Classic with intraspecific interference
    response = ClassicResponse(multiplex_network; c = [0, 0, 0.5], aᵣ = 0.5) # intra interference for species 3
    p = ModelParameters(multiplex_network; functional_response = response)
    fᵣmatrix = p.functional_response(B, multiplex_network)
    eatingᵢ1, being_eatenᵢ1 = Internals.consumption(1, B, p, fᵣmatrix)
    eatingᵢ2, being_eatenᵢ2 = Internals.consumption(2, B, p, fᵣmatrix)
    eatingᵢ3, being_eatenᵢ3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eatingᵢ1 ≈ 0 atol = 1e-5
    @test being_eatenᵢ3 ≈ 0 atol = 1e-5
    @test eatingᵢ2 ≈ eating2 atol = 1e-5 # no change for species 2
    @test eatingᵢ3 < eating3 # decrease of species 3 consumption

    # Classic with interspecific interference
    multiplex_network = MultiplexNetwork(foodweb; C_interference = 1.0) # add interference
    multiplex_network.layers[:interference].intensity = 0.0 # but set i0 to zero in a 1st time
    response = ClassicResponse(multiplex_network; c = [0, 0, 0.5], aᵣ = 0.5) # intra interference
    p = ModelParameters(multiplex_network; functional_response = response)
    fᵣmatrix = p.functional_response(B, multiplex_network)
    # Do we recover previous results?
    eating1_i0_0, being_eaten1_i0_0 = Internals.consumption(1, B, p, fᵣmatrix)
    eating2_i0_0, being_eaten2_i0_0 = Internals.consumption(2, B, p, fᵣmatrix)
    eating3_i0_0, being_eaten3_i0_0 = Internals.consumption(3, B, p, fᵣmatrix)
    @test (eating1_i0_0, being_eaten1_i0_0) == (eatingᵢ1, being_eatenᵢ1)
    @test (eating2_i0_0, being_eaten2_i0_0) == (eatingᵢ2, being_eatenᵢ2)
    @test (eating3_i0_0, being_eaten3_i0_0) == (eatingᵢ3, being_eatenᵢ3)
    # Now set i0 > 0
    multiplex_network.layers[:interference].intensity = 1.0
    response = ClassicResponse(multiplex_network; c = [0, 0, 0.5], aᵣ = 0.5) # intra interference
    p = ModelParameters(multiplex_network; functional_response = response)
    fᵣmatrix = p.functional_response(B, multiplex_network)
    eating1_i0_pos, being_eaten1_i0_pos = Internals.consumption(1, B, p, fᵣmatrix)
    eating2_i0_pos, being_eaten2_i0_pos = Internals.consumption(2, B, p, fᵣmatrix)
    eating3_i0_pos, being_eaten3_i0_pos = Internals.consumption(3, B, p, fᵣmatrix)
    @test eating1_i0_pos == 0
    @test being_eaten1_i0_pos < being_eaten1_i0_0
    @test eating2_i0_pos < eating2_i0_0
    @test being_eaten2_i0_pos < being_eaten2_i0_0
    @test eating3_i0_pos < eating3_i0_0
    @test being_eaten3_i0_pos == 0
end

@testset "Consumption: linear" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0])

    # Bioenergetic - default
    p = ModelParameters(foodweb; functional_response = LinearResponse(foodweb))
    B = [1.0, 1, 1]
    fᵣmatrix = p.functional_response(B)
    eating1, being_eaten1 = Internals.consumption(1, B, p, fᵣmatrix)
    eating2, being_eaten2 = Internals.consumption(2, B, p, fᵣmatrix)
    eating3, being_eaten3 = Internals.consumption(3, B, p, fᵣmatrix)
    @test eating1 ≈ 0 atol = 1e-5 # species 1 does not eat
    @test eating2 == 0.45 * 1 * 1 * 1 # species 2 eats 1 (e*α*Bᵢ*Bⱼ)
    @test eating3 == 0.5 * 0.45 * 1 * 1 * 1 + 0.5 * 0.85 * 1 * 1 * 1
    @test being_eaten3 ≈ 0 atol = 1e-5 # species 3 is not eaten
    @test being_eaten2 == 0.5
    @test being_eaten1 == 1.5

    B₂ = [3.0, 2, 1] # increasing producer biomass...
    fᵣmatrix₂ = p.functional_response(B₂)
    eating1, being_eaten1 = Internals.consumption(1, B₂, p, fᵣmatrix₂)
    eating2, being_eaten2 = Internals.consumption(2, B₂, p, fᵣmatrix₂)
    eating3, being_eaten3 = Internals.consumption(3, B₂, p, fᵣmatrix₂)
    @test eating1 ≈ 0 atol = 1e-5 # species 1 does not eat
    @test eating2 == 0.45 * 1 * 3 * 2 # species 2 eats 1 (e*α*Bᵢ*Bⱼ)
    @test eating3 == 0.5 * 0.45 * 1 * 3 * 1 + 0.5 * 0.85 * 1 * 2 * 1
    @test being_eaten3 ≈ 0 atol = 1e-5 # species 3 is not eaten
    @test being_eaten2 == 0.5 * 2
    @test being_eaten1 == 3 * (0.5 + 2)
end

end

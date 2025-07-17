module FunctionalResponse
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

@testset "Assimilation efficiency" begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0])
    e_expect = sparse([0 0 0; 1 0 0; 1 2 0])
    @test efficiency(foodweb; e_herb = 1, e_carn = 2) == e_expect
    e_expect = sparse([0 0 0; 3 0 0; 3 4 0])
    @test efficiency(foodweb; e_herb = 3, e_carn = 4) == e_expect
    foodweb = FoodWeb([0 0 0; 1 1 0; 1 1 1]; quiet = true)
    e_expect = sparse([0 0 0; 1 2 0; 1 2 2])
    @test efficiency(foodweb; e_herb = 1, e_carn = 2) == e_expect
end

A_2sp = [0 0; 1 0] # 2 eats 1
A_3sp = [0 0 0; 1 0 0; 1 1 0] # 2 eats 1; 3 eats 1 & 2
foodweb_2sp = FoodWeb(A_2sp)
multi_net1 = MultiplexNetwork(foodweb_2sp)
foodweb_3sp = FoodWeb(A_3sp)
net_interference =
    MultiplexNetwork(foodweb_3sp; C_itf = 1.0, intensity = (c = 0, f = 0, i = 0, r = 0))
net_refuge =
    MultiplexNetwork(foodweb_3sp; C_ref = 1.0, intensity = (c = 0, f = 0, i = 0, r = 0))

@testset "Bioenergetic functional response parameters" begin
    # Default
    Fbioenergetic_1 = BioenergeticResponse(foodweb_2sp)
    @test Fbioenergetic_1.B0 == [0.5, 0.5]
    @test Fbioenergetic_1.h == 2.0
    @test Fbioenergetic_1.c == [0.0, 0.0]

    # Custom
    Fbioenergetic_1 = BioenergeticResponse(foodweb_2sp; B0 = 3.0, h = 1.0, c = 0.5)
    @test Fbioenergetic_1.B0 == [3.0, 3.0]
    @test Fbioenergetic_1.h == 1.0
    @test Fbioenergetic_1.c == [0.5, 0.5]

    # Preferency matrix
    Fbioenergetic_2 = BioenergeticResponse(foodweb_3sp)
    @test Fbioenergetic_1.ω == sparse([0 0; 1 0])
    @test Fbioenergetic_2.ω == sparse([0 0 0; 1 0 0; 0.5 0.5 0])
end

@testset "Linear functional response parameters" begin
    # Default
    Flinear_1 = LinearResponse(foodweb_2sp)
    @test Flinear_1.α == sparse([0, 1.0])
    @test Flinear_1.ω == sparse([0 0; 1.0 0.0])

    # Custom
    Flinear_1 = LinearResponse(foodweb_2sp; α = [0.0, 2.0])
    @test Flinear_1.α == sparse([0, 2.0])
    @test Flinear_1.ω == sparse([0 0; 1.0 0.0])

    # Custom and foodweb_3sp
    Flinear_2 = LinearResponse(foodweb_3sp; α = 3.0)
    @test Flinear_2.α == sparse([0, 3.0, 3.0])
    @test Flinear_2.ω == sparse([0 0 0; 1 0 0; 0.5 0.5 0])
end

@testset "Classic functional response parameters" begin
    # Default
    foodweb_default = FoodWeb([0 0 0; 1 0 0; 0 1 0]; Z = 10)
    Fclassic_1 = ClassicResponse(foodweb_default)
    @test Fclassic_1.h == 2.0
    @test Fclassic_1.aᵣ == attack_rate(foodweb_default)
    @test Fclassic_1.hₜ == handling_time(foodweb_default)
    @test Fclassic_1.c == [0.0, 0.0, 0.0]

    # Custom
    Fclassic_1 = ClassicResponse(foodweb_2sp; h = 1.0, aᵣ = [0 0; 0.2 0], hₜ = 5, c = 0.6)
    @test Fclassic_1.h == 1.0
    @test Fclassic_1.aᵣ == sparse([0 0; 0.2 0])
    @test Fclassic_1.hₜ == sparse([0 0; 5 0])
    @test Fclassic_1.c == [0.6, 0.6]

    # Preferency matrix
    Fclassic_2 = ClassicResponse(foodweb_3sp)
    @test Fclassic_1.ω == sparse([0 0; 1 0])
    @test Fclassic_2.ω == sparse([0 0 0; 1 0 0; 0.5 0.5 0])
end

@testset "Bioenergetic functional response functor" begin
    # Index by index - FoodWeb
    Fbioenergetic1_fw = BioenergeticResponse(foodweb_2sp)
    @test Fbioenergetic1_fw([1.0, 1], 1, 1) == 0 # no interaction
    @test Fbioenergetic1_fw([1.0, 1], 1, 2) == 0 # no interaction
    @test Fbioenergetic1_fw([1.0, 1], 2, 2) == 0 # no interaction
    @test Fbioenergetic1_fw([1.0, 1], 2, 1) == 1^2 / (0.5^2 + 1^2) # interaction
    @test Fbioenergetic1_fw([1.0, 2], 2, 1) == 1^2 / (0.5^2 + 1^2) # don't depend on cons. B
    @test Fbioenergetic1_fw([2.0, 1], 2, 1) == 2^2 / (0.5^2 + 2^2) # ...but depend on res. B

    # Index by index - FoodWeb
    Fbioenergetic1_nti = BioenergeticResponse(multi_net1)
    @test Fbioenergetic1_nti([1.0, 1], 1, 1) == 0 # no interaction
    @test Fbioenergetic1_nti([1.0, 1], 1, 2) == 0 # no interaction
    @test Fbioenergetic1_nti([1.0, 1], 2, 2) == 0 # no interaction
    @test Fbioenergetic1_nti([1.0, 1], 2, 1) == 1^2 / (0.5^2 + 1^2) # interaction
    @test Fbioenergetic1_nti([1.0, 2], 2, 1) == 1^2 / (0.5^2 + 1^2) # don't depend on cons. B
    @test Fbioenergetic1_nti([2.0, 1], 2, 1) == 2^2 / (0.5^2 + 2^2) # ...but depend on res. B

    # Matrix
    F21 = 1^2 / (0.5^2 + 1^2)
    @test Fbioenergetic1_fw([1.0, 1]) == sparse([0 0; F21 0]) # provide biomass vector
    @test Fbioenergetic1_fw([1.0, 1], foodweb_2sp) == sparse([0 0; F21 0]) # meth. consistency
    @test Fbioenergetic1_fw([1.0, 1], multi_net1) == sparse([0 0; F21 0]) # meth. consistency
    @test Fbioenergetic1_fw(1.0) == sparse([0 0; F21 0]) # or a scalar if same for all sp

    # Non-default hill exponent
    Fbioenergetic_1 = BioenergeticResponse(foodweb_2sp; h = 3)
    F21 = 2^3 / (0.5^3 + 2^3)
    @test Fbioenergetic_1(2.0) == sparse([0 0; F21 0])
    @test Fbioenergetic_1(2.0, foodweb_2sp) == sparse([0 0; F21 0]) # method consistency
    @test Fbioenergetic_1(2.0, multi_net1) == sparse([0 0; F21 0]) # nti=0 ⟺ foodweb

    # Consumer feeding on several resources
    Fbioenergetic2_fw = BioenergeticResponse(foodweb_3sp)
    Fbioenergetic2_nti = BioenergeticResponse(net_interference)
    B = [1.0, 1, 1] # uniform biomass distribution
    F21 = 1^2 / (0.5^2 + 1^2)
    F31 = 0.5 * 1^2 / ((0.5^2) + (0.5 * 1^2) + (0.5 * 1^2))
    F32 = F31
    @test Fbioenergetic2_fw(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])
    B = [3.0, 2, 1] # non-uniform biomass distribution
    F21 = 3^2 / (0.5^2 + 3^2)
    F31 = 0.5 * 3^2 / ((0.5^2) + (0.5 * 3^2) + (0.5 * 2^2))
    F32 = 0.5 * 2^2 / ((0.5^2) + (0.5 * 3^2) + (0.5 * 2^2))
    @test Fbioenergetic2_fw(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])

    # Adding intraspecific interference
    Fbioenergetic2_fw = BioenergeticResponse(foodweb_3sp; c = 1)
    Fbioenergetic2_nti = BioenergeticResponse(net_interference; c = 1)
    B = [3.0, 2, 1] # non-uniform biomass distribution
    F21 = 3^2 / (0.5^2 + 1 * 2 * 0.5^2 + 3^2)
    F31 = 0.5 * 3^2 / ((0.5^2) + (1 * 1 * 0.5^2) + (0.5 * 3^2 + 0.5 * 2^2))
    F32 = 0.5 * 2^2 / ((0.5^2) + (1 * 1 * 0.5^2) + (0.5 * 3^2 + 0.5 * 2^2))
    @test Fbioenergetic2_fw(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fbioenergetic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])
end

@testset "Linear functional response functor" begin
    # Index by index - FoodWeb
    Flinear1_fw = LinearResponse(foodweb_2sp)
    @test Flinear1_fw([1.0, 1], 1, 1) == 0 # no interaction
    @test Flinear1_fw([1.0, 1], 1, 2) == 0 # no interaction
    @test Flinear1_fw([1.0, 1], 2, 2) == 0 # no interaction
    @test Flinear1_fw([1.0, 1], 2, 1) == 1.0 # interaction
    @test Flinear1_fw([1.0, 2], 2, 1) == 1.0 # don't depend on cons. mass
    @test Flinear1_fw([2.0, 1], 2, 1) == 2.0 # ...but depend on res. mass

    # Index by index - MultiplexNetwork
    Flinear1_nti = LinearResponse(multi_net1)
    @test Flinear1_nti([1.0, 1], 1, 1) == 0 # no interaction
    @test Flinear1_nti([1.0, 1], 1, 2) == 0 # no interaction
    @test Flinear1_nti([1.0, 1], 2, 2) == 0 # no interaction
    @test Flinear1_nti([1.0, 1], 2, 1) == 1.0 # interaction
    @test Flinear1_nti([1.0, 2], 2, 1) == 1.0 # don't depend on cons. mass
    @test Flinear1_nti([2.0, 1], 2, 1) == 2.0 # ...but depend on res. mass

    # Matrix
    @test Flinear1_fw([1.0, 1]) == sparse([0 0; 1.0 0]) # provide biomass vector
    @test Flinear1_fw(1) == sparse([0 0; 1.0 0]) # or a scalar if same for all sp
    @test Flinear1_nti([1, 1]) == sparse([0 0; 1.0 0]) # provide biomass vector
    @test Flinear1_nti(1) == sparse([0 0; 1.0 0]) # or a scalar if same for all sp
    @test Flinear1_nti([1, 1], foodweb_2sp) == sparse([0 0; 1.0 0]) # provide biomass vector
    @test Flinear1_nti([1, 1], multi_net1) == sparse([0 0; 1.0 0]) # or a scalar

    # Non-default consumption rate
    Flinear1_fw = LinearResponse(foodweb_2sp; α = [0, 2.0])
    Flinear1_nti = LinearResponse(multi_net1; α = [0, 2.0])
    @test Flinear1_fw(2) == sparse([0 0; 4.0 0])
    @test Flinear1_nti(2) == sparse([0 0; 4.0 0])

    # Consumer feeding on several resources
    Flinear2_fw = LinearResponse(foodweb_3sp; α = [0, 1, 2])
    Flinear2_nti = LinearResponse(net_interference; α = [0, 1, 2])
    B = [3, 2, 1] # non-uniform biomass distribution
    @test Flinear2_fw(B) == sparse([0 0 0; 3 0 0; 3 2 0])
    @test Flinear2_nti(B) == sparse([0 0 0; 3 0 0; 3 2 0])
end

@testset "Classic functional response functor" begin
    # Index by index - FoodWeb
    Fclassic1_fw = ClassicResponse(foodweb_2sp; hₜ = 1.0, aᵣ = 0.5)
    @test Fclassic1_fw([1.0, 1], 1, 1, 1) == 0 # no interaction
    @test Fclassic1_fw([1.0, 1], 1, 2, 1) == 0 # no interaction
    @test Fclassic1_fw([1.0, 1], 2, 2, 1) == 0 # no interaction
    F21 = (1 * 0.5 * 1^2) / (1 + 0.5 * 1 * 1^2)
    @test Fclassic1_fw([1.0, 1], 2, 1, 1) == F21 # interaction
    @test Fclassic1_fw([1.0, 2], 2, 1, 1) == F21 # don't depend on cons. mass
    @test Fclassic1_fw([1.0, 1], 2, 1, 2) == F21 / 2
    @test Fclassic1_fw([1.0, 1], 2, 1, 3) == F21 / 3
    F21_new = (1 * 0.5 * 2^2) / (1 + 0.5 * 1 * 2^2)
    @test Fclassic1_fw([2.0, 1], 2, 1, 1) == F21_new # ...but depend on res. mass

    # Index by index - MultiplexNetwork
    Fclassic1_nti = ClassicResponse(multi_net1; hₜ = 1.0, aᵣ = 0.5)
    @test Fclassic1_nti([1.0, 1], 1, 1, 1) == 0 # no interaction
    @test Fclassic1_nti([1.0, 1], 1, 2, 1) == 0 # no interaction
    @test Fclassic1_nti([1.0, 1], 2, 2, 1) == 0 # no interaction
    F21 = (1 * 0.5 * 1^2) / (1 + 0.5 * 1 * 1^2)
    @test Fclassic1_nti([1.0, 1], 2, 1, 1) == F21 # interaction
    @test Fclassic1_nti([1.0, 2], 2, 1, 1) == F21 # don't depend on cons. mass
    @test Fclassic1_nti([1.0, 1], 2, 1, 2) == F21 / 2
    @test Fclassic1_nti([1.0, 1], 2, 1, 3) == F21 / 3
    F21_new = (1 * 0.5 * 2^2) / (1 + 0.5 * 1 * 2^2)
    @test Fclassic1_nti([2.0, 1], 2, 1, 1) == F21_new # ...but depend on res. mass

    # Matrix
    @test Fclassic1_fw([1.0, 1], foodweb_2sp) == sparse([0 0; F21 0]) # provide biomass vector
    @test Fclassic1_fw(1.0, foodweb_2sp) == sparse([0 0; F21 0]) # or a scalar
    @test Fclassic1_nti([1.0, 1], multi_net1) == sparse([0 0; F21 0]) # provide biomass vector
    @test Fclassic1_nti(1.0, multi_net1) == sparse([0 0; F21 0]) # or a scalar

    # Non-default hill exponent
    Fclassic_1 = ClassicResponse(foodweb_2sp; h = 3, hₜ = 1.0, aᵣ = 0.5)
    F21 = (1 * 0.5 * 2^3) / (1 + 0.5 * 1 * 2^3)
    @test Fclassic_1(2.0, foodweb_2sp) == sparse([0 0; F21 0])

    # Non-default body mass
    foodweb_2sp_M = FoodWeb(A_2sp; M = [2, 3])
    Fclassic_1 = ClassicResponse(foodweb_2sp; h = 3, hₜ = 1.0, aᵣ = 0.5)
    F21 = (1 * 0.5 * 2^3) / (1 + 0.5 * 1 * 2^3)
    @test Fclassic_1(2.0, foodweb_2sp_M) == sparse([0 0; F21/3 0])

    # Non-default attack rate
    Fclassic_1 = ClassicResponse(foodweb_2sp; aᵣ = 0.2, hₜ = 1.0)
    F21 = (1 * 0.2 * 2^2) / (1 + 0.2 * 1 * 2^2)
    @test Fclassic_1(2.0, foodweb_2sp) == sparse([0 0; F21 0])

    # Non-default handling time
    Fclassic_1 = ClassicResponse(foodweb_2sp; hₜ = 2, aᵣ = 0.5)
    F21 = (1 * 0.5 * 2^2) / (1 + 0.5 * 2 * 2^2)
    @test Fclassic_1(2.0, foodweb_2sp) == sparse([0 0; F21 0])


    # Consumer feeding on several resources
    Fclassic2_fw = ClassicResponse(foodweb_3sp; hₜ = 1.0, aᵣ = 0.5)
    Fclassic2_nti = ClassicResponse(net_interference; hₜ = 1.0, aᵣ = 0.5)
    B = [1.0, 1, 1] # uniform biomass distribution
    F21 = (1 * 0.5 * 1^2) / (1 + 0.5 * 1 * 1^2)
    F31 = (0.5 * 0.5 * 1^2) / (1 + 0.5 * 0.5 * 1 * 1^2 + 0.5 * 0.5 * 1 * 1^2)
    F32 = F31
    @test Fclassic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fclassic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])
    B = [3.0, 2, 1] # non-uniform biomass distribution
    F21 = (1 * 0.5 * 3^2) / (1 + 0.5 * 1 * 3^2)
    F31 = (0.5 * 0.5 * 3^2) / (1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    F32 = (0.5 * 0.5 * 2^2) / (1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    @test Fclassic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fclassic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])
    B, aᵣ = [3.0, 2, 1], [0 0 0; 0.5 0 0; 0.5 0.2 0] # non-uniform biomass...
    Fclassic2_fw = ClassicResponse(foodweb_3sp; aᵣ = aᵣ, hₜ = 1.0) #...and non-uniform attack rate
    Fclassic2_nti = ClassicResponse(net_interference; aᵣ = aᵣ, hₜ = 1.0)
    F21 = (1 * 0.5 * 3^2) / (1 + 0.5 * 1 * 3^2)
    F31 = (0.5 * 0.5 * 3^2) / (1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.2 * 1 * 2^2)
    F32 = (0.5 * 0.2 * 2^2) / (1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.2 * 1 * 2^2)
    @test Fclassic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fclassic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])
    B, hₜ = [3.0, 2, 1], [0 0 0; 0.9 0 0; 0.7 0.2 0] # non-uniform biomass...
    Fclassic2_fw = ClassicResponse(foodweb_3sp; hₜ = hₜ, aᵣ = 0.5) #...+ varying handling time
    Fclassic2_nti = ClassicResponse(net_interference; hₜ = hₜ, aᵣ = 0.5)
    F21 = (1 * 0.5 * 3^2) / (1 + 0.5 * 0.9 * 3^2)
    F31 = (0.5 * 0.5 * 3^2) / (1 + 0.5 * 0.5 * 0.7 * 3^2 + 0.5 * 0.5 * 0.2 * 2^2)
    F32 = (0.5 * 0.5 * 2^2) / (1 + 0.5 * 0.5 * 0.7 * 3^2 + 0.5 * 0.5 * 0.2 * 2^2)
    @test Fclassic2_fw(B, foodweb_3sp) ≈ sparse([0 0 0; F21 0 0; F31 F32 0]) atol = 1e-5
    expect = sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fclassic2_nti(B, net_interference) ≈ expect atol = 1e-5

    # Adding intraspecific interference
    Fclassic2_fw = ClassicResponse(foodweb_3sp; c = 1, hₜ = 1.0, aᵣ = 0.5)
    Fclassic2_nti = ClassicResponse(net_interference; c = 1, hₜ = 1.0, aᵣ = 0.5)
    B = [3.0, 2, 1] # non-uniform biomass distribution
    F21 = (1 * 0.5 * 3^2) / (1 + 1 * 2 + 0.5 * 1 * 3^2)
    F31 = (0.5 * 0.5 * 3^2) / (1 + 1 * 1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    F32 = (0.5 * 0.5 * 2^2) / (1 + 1 * 1 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    @test Fclassic2_fw(B, foodweb_3sp) == sparse([0 0 0; F21 0 0; F31 F32 0])
    @test Fclassic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])

    # Adding interspecific interference
    net_interference.layers[:interference].intensity = 0.6 # activate interspecific interference
    Fclassic2_nti = ClassicResponse(net_interference; c = 0.5, hₜ = 1.0, aᵣ = 0.5)
    B = [3.0, 2, 1] # non-uniform biomass distribution
    F21 = (1 * 0.5 * 3^2) / (1 + 0.5 * 2 + 0.6 * 1 + 0.5 * 1 * 3^2)
    F31 =
        (0.5 * 0.5 * 3^2) /
        (1 + 0.5 * 1 + 0.6 * 2 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    F32 =
        (0.5 * 0.5 * 2^2) /
        (1 + 0.5 * 1 + 0.6 * 2 + 0.5 * 0.5 * 1 * 3^2 + 0.5 * 0.5 * 1 * 2^2)
    @test Fclassic2_nti(B, net_interference) == sparse([0 0 0; F21 0 0; F31 F32 0])

    # Adding refuge provisioning
    Fclassic2_nti = ClassicResponse(net_refuge; c = 0.0, hₜ = 1.0, aᵣ = 0.5)
    Fclassic2_fw = ClassicResponse(foodweb_3sp; c = 0.0, hₜ = 1.0, aᵣ = 0.5)
    B = [3.0, 2, 1]
    @test Fclassic2_fw(B, foodweb_3sp) == Fclassic2_nti(B, net_refuge) # nti intensity = 0 <=> food web
    for r0 in [0.1, 0.2, 0.25]
        net_refuge.layers[:refuge].intensity = r0
        Fclassic2_nti = ClassicResponse(net_refuge; c = 0.0, hₜ = 1.0, aᵣ = 0.5)
        a₃₁, a₃₂, a₂₁ = 0.5, 0.5 / (1 + r0 * B[1]), 0.5
        F21 = (1 * a₂₁ * 3^2) / (1 + a₂₁ * 1 * 3^2)
        F31 = (0.5 * a₃₁ * 3^2) / (1 + 0.5 * a₃₁ * 1 * 3^2 + 0.5 * a₃₂ * 1 * 2^2)
        F32 = (0.5 * a₃₂ * 2^2) / (1 + 0.5 * a₃₁ * 1 * 3^2 + 0.5 * a₃₂ * 1 * 2^2)
        @test Fclassic2_nti(B, net_refuge) == sparse([0 0 0; F21 0 0; F31 F32 0])
    end
end

@testset "Generation of default feeding rates" begin
    # All body masses set to 1, expect 0.3 for each trophic interaction
    foodweb = FoodWeb([0 0 0; 1 0 0; 0 1 0]; M = [1, 1, 1])
    @test handling_time(foodweb) == [0 0 0; 0.3 0 0; 0 0.3 0]
    @test handling_time(foodweb |> MultiplexNetwork) == [0 0 0; 0.3 0 0; 0 0.3 0]
    @test attack_rate(foodweb) == [0 0 0; 50 0 0; 0 50 0]
    @test attack_rate(foodweb |> MultiplexNetwork) == [0 0 0; 50 0 0; 0 50 0]

    # Different body masses, expect different values
    foodweb = FoodWeb([0 0 0; 1 0 0; 0 1 0]; M = [2, 10, 100])
    a = 0.3 * 10^(-0.48) * 2^(-0.66) # expected ht[2,1]
    b = 0.3 * 100^(-0.48) * 10^(-0.66) # expected ht[3,2]
    ht_expected = [
        0 0 0
        a 0 0
        0 b 0
    ]
    c = 50 * 10^(0.45) # expected ar[2,1]
    d = 50 * 100^(0.45) * 10^(0.15) # expected ar[3,2]
    ar_expected = [
        0 0 0
        c 0 0
        0 d 0
    ]
    @test handling_time(foodweb) ≈ ht_expected
    @test handling_time(foodweb |> MultiplexNetwork) ≈ ht_expected
    @test attack_rate(foodweb) ≈ ar_expected
    @test attack_rate(foodweb |> MultiplexNetwork) ≈ ar_expected
end

end

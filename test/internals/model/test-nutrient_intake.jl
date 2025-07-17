module TestNutrientIntake
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

@testset "NutrientIntake: build struct." begin

    foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0])
    ni = NutrientIntake(foodweb)

    # Check default values.
    @test length(ni) == 2
    @test ni.turnover == [0.25, 0.25]
    @test ni.supply == [10.0, 10.0]
    @test ni.concentration == sparse([1 0.5; 1 0.5])
    @test ni.half_saturation == [1.0 1; 1 1]

    # Pass custom values.
    ni = NutrientIntake(
        foodweb;
        n_nutrients = 3,
        half_saturation = 10,
        turnover = 0.8,
        supply = 4,
        concentration = [0.4, 0.1, 0.5],
    )
    @test length(ni) == 3
    @test ni.turnover == fill(0.8, 3)
    @test ni.supply == repeat([4.0], length(ni))
    @test ni.concentration == sparse([0.4 0.1 0.5; 0.4 0.1 0.5])
    @test ni.half_saturation == [10.0 10.0 10.0; 10.0 10.0 10.0]

    ni_1 = NutrientIntake(
        foodweb;
        n_nutrients = 4,
        half_saturation = [1, 1],
        supply = [1, 1, 1, 1],
        concentration = [0.2, 0.2, 0.2, 0.2],
    )
    ni_2 = NutrientIntake(
        foodweb;
        n_nutrients = 4,
        half_saturation = ones(2, 4),
        supply = 1,
        concentration = 0.2,
    )
    @test length(ni_1) == length(ni_2) == 4
    @test ni_1.turnover == ni_2.turnover == fill(0.25, 4)

    # `half_saturation` is a matrix of size (n_producers, n_nutrients)
    @test ni_1.half_saturation == ni_2.half_saturation == [ # size = (n_prod, n_nutrients).
        1.0 1.0 1.0 1.0
        1.0 1.0 1.0 1.0
    ]
    # `supply` is a vector of length n_nutrients.
    @test ni_1.supply == ni_2.supply == [1.0, 1.0, 1.0, 1.0]
    # `concentration` is a matrix of size (n_producers, n_nutrients)
    @test ni_1.concentration == ni_2.concentration == fill(0.2, 2, 4)

    # Error if arguments have the wrong dimensions.
    @test_throws ArgumentError NutrientIntake(foodweb, half_saturation = [1, 1, 1])
    @test_throws ArgumentError NutrientIntake(foodweb, half_saturation = [1 1 1; 1 1 1])
    @test_throws ArgumentError NutrientIntake(foodweb, supply = [1 1 1])
    @test_throws ArgumentError NutrientIntake(foodweb, concentration = [1 1 1])
    @test_throws ArgumentError NutrientIntake(
        foodweb,
        n_nutrients = 3,
        concentration = [1 1; 1 1; 1 1],
    )
end

@testset "NutrientIntake: functor." begin

    foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0])
    ni = NutrientIntake(foodweb)
    model = ModelParameters(foodweb; producer_growth = ni)
    n = total_richness(model)
    u = fill(0, n) # Species biomass and nutrient abundances.
    # If all abundances are set to 0, then the growth term is null.
    @test ni(1, u, model) == ni(2, u, model) == 0

    # If nutrient abundance and species biomass are strictly positive,
    # then the growth is also positive and increase the producer biomass.
    N = ones(2) # Nutrient abundances.
    B = [1, 2, rand()] # Species abundances.
    u = vcat(B, N)
    @test 0 < ni(1, u, model) < ni(2, u, model)
    @test ni(3, u, model) == 0 # Growth term is null non-producers.

    # Test a specific case.
    N = rand(2)
    B = rand(3)
    u = vcat(B, N)
    half_saturation = rand(2)
    ni = NutrientIntake(foodweb; half_saturation)
    model = ModelParameters(foodweb; producer_growth = ni)
    expectations = [B[i] * minimum(N ./ (ni.half_saturation[i, :] .+ N)) for i in 1:2]
    push!(expectations, 0) # Zero growth is expected for species 3 (consumer).
    for i in 1:3
        @test ni(i, u, model) == expectations[i]
    end
end

@testset "NutrientIntake: dynamics." begin

    # Consumer goes extinct if there is no supply.
    # Producer do not as long as there are no metabolic losses or mortality outside
    # of consumption.
    foodweb = FoodWeb([0 0 0; 1 0 0; 0 1 0])
    ni = NutrientIntake(foodweb; supply = 0.0)
    S = richness(foodweb)
    model = ModelParameters(foodweb; producer_growth = ni)
    B0 = ones(S)
    N0 = ones(nutrient_richness(model))
    sim = simulates(model, B0; N0)
    @test sim.u[end][2:3] == [0.0, 0.0]

    # In the absence of consumers, all biomasses are equal (for equal growth parameters).
    foodweb = FoodWeb([0 0; 0 0])
    producer_growth = NutrientIntake(foodweb)
    model = ModelParameters(foodweb; producer_growth)
    B0 = ones(2)
    N0 = ones(2)
    sol = simulates(model, B0; N0)
    traj = reduce(hcat, sol.u) # row = species & nutrients, col = time steps.
    sp = species_indices(model) # Species indexes.
    @test all(traj[sp[1], :] .== traj[sp[2], :])

    # `half_saturation` sets the hierarchy of competition between producers.
    # The smaller the half saturation, the larger the producer grows.
    producer_growth = NutrientIntake(foodweb; half_saturation = [0.1 0.1; 0.5 0.5])
    model = ModelParameters(foodweb; producer_growth)
    B0 = ones(2)
    N0 = ones(2)
    sol = simulates(model, B0; N0)
    @test sol.u[end][1] > sol.u[end][2]
end

end

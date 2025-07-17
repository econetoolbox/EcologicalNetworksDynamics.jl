module Productivity
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "LogisticGrowth functor" begin

    foodweb_to_test = [
        FoodWeb([0 0; 0 0]; quiet = true), # 2 producers.
        FoodWeb([0 0 0; 0 0 0; 1 1 0]; quiet = true), # 2 producers and 1 consumer.
    ]

    for (i, network) in enumerate(foodweb_to_test), f0 in [0, rand()]
        # Default behaviour.
        S = richness(network)
        A = zeros(Integer, S, S)
        A[1, 2] = A[2, 1] = 1
        f0 > 0 && (network = MultiplexNetwork(network; facilitation = (A = A, I = f0)))
        functional_response = ClassicResponse(network)
        model = ModelParameters(network; functional_response)
        g = model.producer_growth
        @test isa(g, LogisticGrowth)
        u = rand(richness(model))
        @test g(1, u, model) == (1 + f0 * u[2]) * u[1] * (1 - u[1] / 1)
        @test g(2, u, model) == (1 + f0 * u[1]) * u[2] * (1 - u[2] / 1)
        i == 2 && @test g(3, u, model) == 0.0

        # Change carrying capacity and intrinsic growth rate.
        K = [isproducer(i, network) ? 1 + rand() : nothing for i in species_indices(model)]
        r = [isproducer(i, network) ? rand() : 0 for i in species_indices(model)]
        g = LogisticGrowth(network; K)
        biorates = BioRates(network; r)
        model = ModelParameters(network; producer_growth = g, biorates, functional_response)
        @test g(1, u, model) == r[1] * (1 + f0 * u[2]) * u[1] * (1 - u[1] / K[1])
        @test g(2, u, model) == r[2] * (1 + f0 * u[1]) * u[2] * (1 - u[2] / K[2])
        i == 2 && @test g(3, u, model) == 0.0

        # With producer competition.
        # Change intra-specific competition only.
        a_ii = rand()
        g = LogisticGrowth(network; a = a_ii)
        model = ModelParameters(network; producer_growth = g, functional_response)
        @test g(1, u, model) == 1 * (1 + f0 * u[2]) * u[1] * (1 - (a_ii * u[1]) / 1)
        @test g(2, u, model) == 1 * (1 + f0 * u[1]) * u[2] * (1 - (a_ii * u[2]) / 1)
        # Change intra and inter-specific competition.
        a_ii, a_ij = rand(2)
        g = LogisticGrowth(network; a = (a_ii, a_ij))
        model = ModelParameters(network; producer_growth = g, functional_response)
        s1 = a_ii * u[1] + a_ij * u[2]
        s2 = a_ii * u[2] + a_ij * u[1]
        @test g(1, u, model) == 1 * (1 + f0 * u[2]) * u[1] * (1 - s1 / 1)
        @test g(2, u, model) == 1 * (1 + f0 * u[1]) * u[2] * (1 - s2 / 1)
        i == 2 && @test g(3, u, model) == 0.0
    end

    # Test a simple simulation with producer competition.
    foodweb = FoodWeb([0 0 0; 0 0 0; 0 0 1]; quiet = true)
    biorates = BioRates(foodweb; d = 0)
    producer_growth = LogisticGrowth(foodweb; a = (diag = 1, offdiag = 1))
    model = ModelParameters(foodweb; producer_growth, biorates)
    u0 = 0.5 # All species have an initial biomass of u0.
    sol = simulates(model, u0; verbose = false)
    @test sol[1:2, end] == [0.5, 0.5]

    # Test a simulation with only inter-specific producer competition and
    # another simulation with only intra-specific competition.
    kwargs = [Dict(:a => (0, 1)), Dict(:a => (1, 0))]
    for kw in kwargs
        producer_growth = LogisticGrowth(foodweb; kw...)
        model = ModelParameters(foodweb; producer_growth, biorates)
        sol = simulates(model, u0; verbose = false)
        @test sol[1:2, end] ≈ [1, 1]
    end

end

end

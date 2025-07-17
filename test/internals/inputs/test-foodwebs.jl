module FoodWebs
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "Foodwebs from adjacency list." begin
    function test_on_iterable_pair(
        pair_tuple,
        expected_A;
        expected_names = nothing,
        kwargs...,
    )
        pair_vector = [i => j for (i, j) in pair_tuple]
        pair_dict = Dict(pair_vector)
        for pair_iter in [pair_tuple, pair_vector, pair_dict]
            fw = FoodWeb(pair_iter; kwargs...)
            @test fw.A == expected_A
            isnothing(expected_names) || @test fw.species == expected_names
        end
    end

    # Indexes
    pair_tuple = (1 => 2, 2 => [2, 3], 3 => (3, 4))
    expected_A = [0 1 0 0; 0 1 1 0; 0 0 1 1; 0 0 0 0]
    test_on_iterable_pair(pair_tuple, expected_A; quiet = true)

    # Labels
    pair_tuple = (:b => [:b, :c], :c => [:c, :d], :a => :b)
    expected_names = ["a", "b", "c", "d"]
    test_on_iterable_pair(
        pair_tuple,
        expected_A;
        expected_names = expected_names,
        quiet = true,
    )

    # For labels, we can mix Symbols and Strings
    pair_tuple = (:b => [:b, :c], "c" => [:c, "d"], :a => "b")
    test_on_iterable_pair(
        pair_tuple,
        expected_A;
        expected_names = expected_names,
        quiet = true,
    )

    # Provide labels for the index used. Order matters.
    species = [:mussel, :crab]
    pairs = [2 => 1]
    expected_A = [0 0; 1 0]
    test_on_iterable_pair(
        pairs,
        expected_A;
        expected_names = String.(species),
        species = species,
    )

    # Don't provide both labels in `species` argument and adjacency list.
    @test_throws ArgumentError FoodWeb([:crab => :mussel]; species = species)

end

# Check that foodwebs are correctly constructed from structural models,
# and that the desired number of links and connectance are respected for various inputs.
@testset "FoodWebs from structural model." begin
    n_rep = 20
    SL_tuple = [(10, 20), (15, 20), (15, 30), (20, 50)]
    for model in [niche_model, cascade_model]
        for (S, L) in SL_tuple
            for tL in 0:3
                # From number of links (L)
                n_link_vec =
                    [n_links(FoodWeb(model, S; L = L, tol_L = tL)) for i in 1:n_rep]
                @test all((L - tL) .<= n_link_vec .<= (L + tL))
                # From connectance (C)
                tC = tL / S^2
                C = L / S^2
                c_vec = [
                    Internals.connectance(FoodWeb(model, S; C = C, tol_C = tC)) for
                    i in 1:n_rep
                ]
                @test all((C - tC) .<= c_vec .<= (C + tC))
            end
        end
    end

    # Cannot provide both number of links (L) and connectance.
    @test_throws ArgumentError FoodWeb(niche_model, 10, C = 0.1, L = 10)

    # Cannot provide both tolerance on number of links (tol_L) and connectance (tol_C).
    @test_throws ArgumentError FoodWeb(niche_model, 10, C = 0.1, tol_L = 1, tol_C = 0.01)
    @test_throws ArgumentError FoodWeb(niche_model, 10, L = 10, tol_L = 1, tol_C = 0.01)

    # Cannot provide a number of links and a tolerance on the connectance.
    @test_throws ArgumentError FoodWeb(niche_model, 10, L = 10, tol_C = 0.01)

    # Cannot provide a connectance and a tolerance on the number of links.
    @test_throws ArgumentError FoodWeb(niche_model, 10, C = 0.1, tol_L = 1)
end

@testset "Warning if foodweb has disconnected species." begin
    A_throwing_warning = [
        [0 0 0; 1 0 0; 0 0 0], # species 3 is disconnected
        [0 0; 0 0], # 2 disconnected species
    ]
    for A in A_throwing_warning
        @test_logs (:warn,) FoodWeb(A) # warning expected
        @test_logs FoodWeb(A, quiet = true) # 'quiet' arg silent the warning
    end

    A_no_warning = [[0 0; 1 0], [0 0 0; 1 0 0; 0 1 0], [2 => 1, 3 => [1, 2]]]
    for A in A_no_warning
        @test_logs FoodWeb(A)
    end

    # Test when the FoodWeb is generated with a structural model.
    @test_logs (:warn,) FoodWeb(niche_model, 10; C = 0.0, check_disconnected = false)
    @test_logs FoodWeb(niche_model, 10; C = 0.0, check_disconnected = false, quiet = true)
end

end

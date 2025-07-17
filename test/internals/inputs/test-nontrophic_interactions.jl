module NonTrophicInteractions
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

@testset "Non-trophic Interactions: build MultiplexNetwork." begin

    # Basic structure.
    foodweb = FoodWeb([0 0; 1 0]) # 2 eats 1
    multiplex_net = MultiplexNetwork(foodweb) # default net w/o non-trophic interactions
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    for A in [A_competition, A_facilitation, A_interference, A_refuge]
        @test isempty(A.nzval)
    end
    @test multiplex_net.layers[:trophic].A == foodweb.A
    @test multiplex_net.M == foodweb.M
    @test multiplex_net.species == foodweb.species

    # Build from connectance.
    foodweb = FoodWeb(niche_model, 20; C = 0.1)
    # - Only facilitation on.
    multiplex_net = MultiplexNetwork(foodweb; C_facilitation = 0.5)
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    A_list = [A_competition, A_facilitation, A_interference, A_refuge]
    for (f, A) in zip([isempty, !isempty, isempty, isempty], A_list)
        @test f(A.nzval)
    end
    # - Refuge and competition on.
    multiplex_net = MultiplexNetwork(foodweb; C_competition = 0.5, C_refuge = 0.5)
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    A_list = [A_competition, A_facilitation, A_interference, A_refuge]
    for (f, A) in zip([!isempty, isempty, isempty, !isempty], A_list)
        @test f(A.nzval)
    end
    # - Everything on.
    multiplex_net = MultiplexNetwork(foodweb; C = (f = 0.5, c = 0.5, r = 0.5, i = 0.5))
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    for A in [A_competition, A_facilitation, A_interference, A_refuge]
        @test !isempty(A.nzval)
    end

    # Build from links.
    foodweb = FoodWeb([0 0 0 0; 0 0 0 0; 1 0 0 0; 1 0 0 0]; quiet = true)
    # - Only facilitation on.
    multiplex_net = MultiplexNetwork(foodweb; L_facilitation = 1)
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    A_list = [A_competition, A_facilitation, A_interference, A_refuge]
    for (L, A) in zip([0, 1, 0, 0], A_list)
        @test length(A.nzval) == L
    end

    # - Refuge and competition on.
    multiplex_net_l = MultiplexNetwork(foodweb; L_competition = 2, L_refuge = 1)
    multiplex_net_lc = MultiplexNetwork(foodweb; C_competition = 1.0, L_refuge = 1)
    for multiplex_net in [multiplex_net_l, multiplex_net_lc]
        A_competition = multiplex_net.layers[:competition].A
        A_facilitation = multiplex_net.layers[:facilitation].A
        A_interference = multiplex_net.layers[:interference].A
        A_refuge = multiplex_net.layers[:refuge].A
        A_list = [A_competition, A_facilitation, A_interference, A_refuge]
        for (L, A) in zip([2, 0, 0, 1], A_list)
            @test length(A.nzval) == L
        end
    end

    # Error if provide connectance and number of links for the same interaction
    @test_throws ArgumentError MultiplexNetwork(foodweb, L_refuge = 1, C_refuge = 0.5)

    # - Everything on.
    multiplex_net = MultiplexNetwork(foodweb; L = (f = 1, c = 2, r = 1, i = 2))
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    A_list = [A_competition, A_facilitation, A_interference, A_refuge]
    for (L, A) in zip([2, 1, 2, 1], A_list)
        @test length(A.nzval) == L
    end

    # Build with specifying specific non-trophic matrices.
    foodweb = FoodWeb(niche_model, 20; C = 0.1)
    custom_matrix = zeros(20, 20)
    custom_matrix[4, 5] = 1
    # - Only facilitation.
    multiplex_net = MultiplexNetwork(foodweb; A_facilitation = custom_matrix)
    @test multiplex_net.layers[:facilitation].A == sparse(custom_matrix)
    A_competition = multiplex_net.layers[:competition].A
    A_interference = multiplex_net.layers[:interference].A
    A_refuge = multiplex_net.layers[:refuge].A
    for A in [A_competition, A_interference, A_refuge]
        @test isempty(A.nzval)
    end
    # - Refuge custom, facilitation on.
    multiplex_net =
        MultiplexNetwork(foodweb; A_refuge = custom_matrix, C_facilitation = 0.5)
    @test multiplex_net.layers[:refuge].A == sparse(custom_matrix)
    A_competition = multiplex_net.layers[:competition].A
    A_facilitation = multiplex_net.layers[:facilitation].A
    A_interference = multiplex_net.layers[:interference].A
    A_list = [A_competition, A_facilitation, A_interference]
    for (f, A) in zip([isempty, !isempty, isempty], A_list)
        @test f(A.nzval)
    end
end

@testset "Non-trophic Interactions: find potential links." begin

    # Facilitation.
    foodweb = FoodWeb([0 0; 1 0]) # 2 eats 1
    @test Set(potential_facilitation_links(foodweb)) == Set([(2, 1)]) # 2 can facilitate 1

    foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0]) # 1 & 2 producers
    expect = Set([(1, 2), (2, 1), (3, 1), (3, 2)])
    @test Set(potential_facilitation_links(foodweb)) == expect

    foodweb = FoodWeb([0 0 0 0; 0 0 0 0; 0 0 0 0; 1 1 1 0]) # 1, 2 & 3 producers
    expect = Set([(1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2), (4, 1), (4, 2), (4, 3)])
    @test Set(potential_facilitation_links(foodweb)) == expect

    # Competition.
    expect = Set([(1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2)])
    @test Set(potential_competition_links(foodweb)) == expect

    # Refuge.
    expect = Set([(1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2)])
    @test Set(potential_refuge_links(foodweb)) == expect
    foodweb = FoodWeb([0 0 0 0; 0 0 0 0; 1 1 0 0; 0 0 1 0])
    expect = Set([(1, 2), (2, 1), (1, 3), (2, 3)])
    @test Set(potential_refuge_links(foodweb)) == expect

    # Interference.
    foodweb = FoodWeb([0 0 0 0; 1 0 0 0; 1 0 0 0; 0 0 0 0]; quiet = true)
    expect = Set([(2, 3), (3, 2)])
    @test Set(potential_interference_links(foodweb)) == expect
    foodweb = FoodWeb([0 0 0 0; 1 0 0 0; 1 0 0 0; 1 0 0 0])
    expect = Set([(2, 3), (3, 2), (4, 3), (3, 4), (4, 2), (2, 4)])
    @test Set(potential_interference_links(foodweb)) == expect
    foodweb = FoodWeb([0 0 0 0; 1 0 0 0; 0 1 0 0; 1 1 0 0])
    expect = Set([(4, 3), (3, 4), (4, 2), (2, 4)])
    @test Set(potential_interference_links(foodweb)) == expect
end

@testset "Non-trophic Interactions: draw randomly links." begin
    foodweb = FoodWeb([0 0 0 0; 0 0 0 0; 0 0 0 0; 1 1 1 0]) # 1, 2 & 3 producers

    # Asymmetric interaction.
    potential_links = potential_facilitation_links(foodweb)
    Lmax = length(potential_links)

    # - From number of links (L).
    for L in 0:9
        drawn_links = draw_asymmetric_links(potential_links, L)
        @test length(drawn_links) == L
        @test drawn_links ⊆ Set(potential_links)
    end
    @test_throws ArgumentError draw_asymmetric_links(potential_links, -1)
    @test_throws ArgumentError draw_asymmetric_links(potential_links, Lmax + 1)

    # - From connectance (C).
    for L in 1:9
        drawn_links = draw_asymmetric_links(potential_links, L / Lmax)
        @test length(drawn_links) == L
        @test drawn_links ⊆ Set(potential_links)
    end
    @test_throws ArgumentError draw_asymmetric_links(potential_links, -0.1)
    @test_throws ArgumentError draw_asymmetric_links(potential_links, 1.1)

    # Symmetric interaction.
    potential_links = potential_competition_links(foodweb)
    Lmax = length(potential_links)

    # - From number of links (L).
    for L in 0:2:6
        drawn_links = draw_symmetric_links(potential_links, L)
        @test length(drawn_links) == L
        @test drawn_links ⊆ Set(potential_links)
    end
    @test_throws ArgumentError draw_symmetric_links(potential_links, -1)
    @test_throws ArgumentError draw_symmetric_links(potential_links, Lmax + 1)

    # - From connectance (C).
    for L in 2:2:6
        drawn_links = draw_symmetric_links(potential_links, L / Lmax)
        @test length(drawn_links) == L
        @test drawn_links ⊆ Set(potential_links)
    end
    @test_throws ArgumentError draw_symmetric_links(potential_links, -0.1)
    @test_throws ArgumentError draw_symmetric_links(potential_links, 1.1)
end

@testset "Non-trophic Interactions: build non-trophic adjacency matrix." begin
    foodweb = FoodWeb([0 0 0 0; 0 0 0 0; 0 0 0 0; 1 1 1 0]) # 1, 2 & 3 producers

    # Asymmetric interaction.
    potential_links = potential_facilitation_links(foodweb)
    Lmax = length(potential_links)

    # - From number of links.
    A = nontrophic_adjacency_matrix(
        foodweb,
        potential_facilitation_links,
        5;
        symmetric = false,
    )
    row, col = findnz(A)
    subset = Set([(row[i], col[i]) for i in 1:length(row)])
    @test length(A.nzval) == 5
    @test subset ⊆ Set(potential_links)

    # - From connectance.
    A = nontrophic_adjacency_matrix(
        foodweb,
        potential_facilitation_links,
        6 / Lmax;
        symmetric = false,
    )
    row, col = findnz(A)
    subset = Set([(row[i], col[i]) for i in 1:length(row)])
    @test length(A.nzval) == 6
    @test subset ⊆ Set(potential_links)

    # Symmetric interaction.
    potential_links = potential_competition_links(foodweb)
    Lmax = length(potential_links)

    # - From number of links.
    A = nontrophic_adjacency_matrix(
        foodweb,
        potential_competition_links,
        4;
        symmetric = true,
    )
    row, col = findnz(A)
    subset = Set([(row[i], col[i]) for i in 1:length(row)])
    @test length(A.nzval) == 4
    @test subset ⊆ Set(potential_links)

    # - From connectance.
    A = nontrophic_adjacency_matrix(
        foodweb,
        potential_competition_links,
        6 / Lmax;
        symmetric = true,
    )
    row, col = findnz(A)
    subset = Set([(row[i], col[i]) for i in 1:length(row)])
    @test length(A.nzval) == 6
    @test subset ⊆ Set(potential_links)
end

end

module TestNetworkTopologies

using Test
using SparseArrays
using EcologicalNetworksDynamics.Networks

function check_adjacent(top, (nodes, nb), n, expected)
    actual = collect(nodes(top, n))
    @test length(actual) == nb(top, n)
    @test expected == actual
end

check_targets(top, src, exp) = check_adjacent(top, (target_nodes, n_targets), src, exp)
check_sources(top, tgt, exp) = check_adjacent(top, (source_nodes, n_sources), tgt, exp)
check_neighbours(top, n, exp) = check_adjacent(top, (neighbour_nodes, n_neighbours), n, exp)

function check_nested(it, expected)
    actual = [node => collect(neighbours) for (node, neighbours) in it]
    @test expected == actual
end

@testset "Sparse foreign topology" begin

    # Same two construction inputs.
    a = Bool[
        0 0 0 1
        0 1 0 0
        0 0 0 0
        0 1 0 1
        1 0 0 1
    ]
    b = sparse([
        0 0 0 1
        0 2 0 0
        0 0 0 0
        0 3 0 4
        5 0 0 6
    ])

    for input in (a, b)

        sf = SparseForeign(input)

        @test n_sources(sf) == 5
        @test n_targets(sf) == 4
        @test n_edges(sf) == 6

        # Forward.
        check_targets(sf, 1, [4])
        check_targets(sf, 2, [2])
        check_targets(sf, 3, [])
        check_targets(sf, 4, [2, 4])
        check_targets(sf, 5, [1, 4])

        # Backward.
        check_sources(sf, 1, [5])
        check_sources(sf, 2, [2, 4])
        check_sources(sf, 3, [])
        check_sources(sf, 4, [1, 4, 5])

        @test !is_edge(sf, 1, 1)
        @test !is_edge(sf, 3, 2)
        @test !is_edge(sf, 3, 4)
        @test is_edge(sf, 4, 2)
        @test is_edge(sf, 4, 4)
        @test is_edge(sf, 1, 4)
        @test is_edge(sf, 5, 1)

        # Row-wise edges ordering.
        @test 1 == edge(sf, 1, 4)
        @test 2 == edge(sf, 2, 2)
        @test 3 == edge(sf, 4, 2)
        @test 4 == edge(sf, 4, 4)
        @test 5 == edge(sf, 5, 1)
        @test 6 == edge(sf, 5, 4)
        @test collect(edges(sf)) == [
            (1, 4)
            (2, 2)
            (4, 2)
            (4, 4)
            (5, 1)
            (5, 4)
        ]

        # Nested iterators.
        check_nested(
            forward(sf),
            [
                1 => [(4, 1)]
                2 => [(2, 2)]
                3 => [] # Don't skip by default.
                4 => [(2, 3), (4, 4)]
                5 => [(1, 5), (4, 6)]
            ],
        )

        check_nested(
            forward(sf; skip = true),
            [
                1 => [(4, 1)]
                2 => [(2, 2)]
                4 => [(2, 3), (4, 4)]
                5 => [(1, 5), (4, 6)]
            ],
        )

        check_nested(
            backward(sf),
            [
                1 => [(5, 5)]
                2 => [(2, 2), (4, 3)]
                3 => []
                4 => [(1, 1), (4, 4), (5, 6)]
            ],
        )

        check_nested(
            backward(sf; skip = true),
            [
                1 => [(5, 5)]
                2 => [(2, 2), (4, 3)]
                4 => [(1, 1), (4, 4), (5, 6)]
            ],
        )

    end

end

# Same interface check with another variant.
@testset "Sparse reflexive topology" begin

    # Same two construction inputs.
    a = Bool[
        0 0 0 0
        1 1 0 0
        1 0 0 0
        1 1 0 1
    ]
    b = sparse([
        0 0 0 0
        1 2 0 0
        3 0 0 0
        4 5 0 6
    ])

    for input in (a, b)
        sr = SparseReflexive(input)

        @test n_nodes(sr) == n_sources(sr) == n_targets(sr) == 4
        @test n_edges(sr) == 6

        # Forward.
        check_targets(sr, 1, [])
        check_targets(sr, 2, [1, 2])
        check_targets(sr, 3, [1])
        check_targets(sr, 4, [1, 2, 4])

        # Backward.
        check_sources(sr, 1, [2, 3, 4])
        check_sources(sr, 2, [2, 4])
        check_sources(sr, 3, [])
        check_sources(sr, 4, [4])

        @test !is_edge(sr, 1, 2)
        @test !is_edge(sr, 3, 2)
        @test !is_edge(sr, 4, 3)
        @test is_edge(sr, 2, 1)
        @test is_edge(sr, 2, 2)
        @test is_edge(sr, 4, 4)

        # Row-wise edges ordering.
        @test 1 == edge(sr, 2, 1)
        @test 2 == edge(sr, 2, 2)
        @test 3 == edge(sr, 3, 1)
        @test 4 == edge(sr, 4, 1)
        @test 5 == edge(sr, 4, 2)
        @test 6 == edge(sr, 4, 4)
        @test collect(edges(sr)) == [
            (2, 1)
            (2, 2)
            (3, 1)
            (4, 1)
            (4, 2)
            (4, 4)
        ]

        # Nested iterators.
        check_nested(
            forward(sr),
            [
                1 => [] # Don't skip by default.
                2 => [(1, 1), (2, 2)]
                3 => [(1, 3)]
                4 => [(1, 4), (2, 5), (4, 6)]
            ],
        )

        check_nested(
            forward(sr; skip = true),
            [
                2 => [(1, 1), (2, 2)]
                3 => [(1, 3)]
                4 => [(1, 4), (2, 5), (4, 6)]
            ],
        )

        check_nested(
            backward(sr),
            [
                1 => [(2, 1), (3, 3), (4, 4)]
                2 => [(2, 2), (4, 5)]
                3 => []
                4 => [(4, 6)]
            ],
        )

        check_nested(
            backward(sr; skip = true),
            [
                1 => [(2, 1), (3, 3), (4, 4)]
                2 => [(2, 2), (4, 5)]
                4 => [(4, 6)]
            ],
        )

    end

end

@testset "Sparse symmetric topology" begin

    # Same two construction inputs.
    # Upper triangle is ignored.
    a = Bool[
        0 0 1 1
        1 1 1 1
        0 0 0 0
        1 1 0 1
    ]
    b = sparse([
        0 0 9 9
        1 2 9 9
        0 0 0 0
        3 4 0 5
    ])

    for input in (a, b)
        sm = SparseSymmetric(input)

        @test n_nodes(sm) == n_sources(sm) == n_targets(sm) == 4
        @test n_edges(sm) == 5

        # No direction = all directions are the same.
        for check in (check_targets, check_sources, check_neighbours)
            check(sm, 1, [2, 4])
            check(sm, 2, [1, 2, 4])
            check(sm, 3, [])
            check(sm, 4, [1, 2, 4])
        end

        # Symmetric edges.
        @test !is_edge(sm, 1, 1)
        @test !is_edge(sm, 3, 2)
        @test !is_edge(sm, 2, 3) # Upper triangle ignored in input.
        @test !is_edge(sm, 4, 3)
        @test !is_edge(sm, 3, 4)
        @test is_edge(sm, 1, 2)
        @test is_edge(sm, 2, 1)
        @test is_edge(sm, 2, 2)
        @test is_edge(sm, 4, 2)
        @test is_edge(sm, 2, 4)
        @test is_edge(sm, 4, 4)

        # Row-wise, lower-triangular edges ordering.
        @test 1 == edge(sm, 2, 1)
        @test 2 == edge(sm, 2, 2)
        @test 3 == edge(sm, 4, 1)
        @test 4 == edge(sm, 4, 2)
        @test 5 == edge(sm, 4, 4)
        @test collect(edges(sm)) == [
            (2, 1)
            (2, 2)
            (4, 1)
            (4, 2)
            (4, 4)
        ]

        # Nested iterators, without a direction.
        for nested in (forward, backward, adjacency)
            check_nested(
                nested(sm),
                [
                    1 => [(2, 1), (4, 3)]
                    2 => [(1, 1), (2, 2), (4, 4)]
                    3 => [] # Don't skip by default.
                    4 => [(1, 3), (2, 4), (4, 5)]
                ],
            )
            check_nested(
                nested(sm; skip = true),
                [
                    1 => [(2, 1), (4, 3)]
                    2 => [(1, 1), (2, 2), (4, 4)]
                    4 => [(1, 3), (2, 4), (4, 5)]
                ],
            )
        end

        # Additional option to only yield lower edges directions
        # so that every edge is only yielded once.
        check_nested(
            adjacency(sm; upper = false),
            [
                1 => []
                2 => [(1, 1), (2, 2)]
                3 => []
                4 => [(1, 3), (2, 4), (4, 5)]
            ],
        )
        check_nested(
            adjacency(sm; upper = false, skip = true),
            [
                2 => [(1, 1), (2, 2)]
                4 => [(1, 3), (2, 4), (4, 5)]
            ],
        )

    end
end

end

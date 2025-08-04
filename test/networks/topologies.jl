module TestNetworkTopologies

using Test
using SparseArrays
using EcologicalNetworksDynamics.Networks

function check_adjacent(top, (nodes, nb), n, expected)
    actual = collect(nodes(top, n))
    @test length(actual) == nb(top, n)
    @test expected == actual
    true
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

@testset "Full foreign topology." begin

    ff = FullForeign(4, 5)
    @test n_sources(ff) == 4
    @test n_targets(ff) == 5
    @test n_edges(ff) == 4 * 5

    # Uniform edges: all inside.
    @test all(check_targets(ff, s, 1:5) for s in 1:4)
    @test all(check_sources(ff, t, 1:4) for t in 1:5)
    @test all(is_edge(ff, s, t) for s in 1:4 for t in 1:5)
    @test collect(edges(ff)) == [(s, t) for s in 1:4 for t in 1:5]

    # Nested iterators.
    for skip in [true, false] # (indifferent)
        check_nested(
            forward(ff; skip),
            [
                1 => [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)],
                2 => [(1, 6), (2, 7), (3, 8), (4, 9), (5, 10)],
                3 => [(1, 11), (2, 12), (3, 13), (4, 14), (5, 15)],
                4 => [(1, 16), (2, 17), (3, 18), (4, 19), (5, 20)],
            ],
        )
        check_nested(
            backward(ff; skip),
            [
                1 => [(1, 1), (2, 6), (3, 11), (4, 16)],
                2 => [(1, 2), (2, 7), (3, 12), (4, 17)],
                3 => [(1, 3), (2, 8), (3, 13), (4, 18)],
                4 => [(1, 4), (2, 9), (3, 14), (4, 19)],
                5 => [(1, 5), (2, 10), (3, 15), (4, 20)],
            ],
        )
    end

end

@testset "Full reflexive topology" begin

    fr = FullReflective(4)
    @test n_nodes(fr) == n_sources(fr) == n_targets(fr) == 4
    @test n_edges(fr) == 4^2

    # Forward.
    @test all(check_targets(fr, src, 1:4) for src in 1:4)
    @test all(check_sources(fr, tgt, 1:4) for tgt in 1:4)
    @test all(is_edge(fr, s, t) for s in 1:4 for t in 1:4)
    @test collect(edges(fr)) == [(s, t) for s in 1:4 for t in 1:4]

    # Nested iterators.
    for skip in [true, false] # (indifferent)
        check_nested(
            forward(fr; skip),
            [
                1 => [(1, 1), (2, 2), (3, 3), (4, 4)],
                2 => [(1, 5), (2, 6), (3, 7), (4, 8)],
                3 => [(1, 9), (2, 10), (3, 11), (4, 12)],
                4 => [(1, 13), (2, 14), (3, 15), (4, 16)],
            ],
        )
        check_nested(
            backward(fr; skip),
            [
                1 => [(1, 1), (2, 5), (3, 9), (4, 13)],
                2 => [(1, 2), (2, 6), (3, 10), (4, 14)],
                3 => [(1, 3), (2, 7), (3, 11), (4, 15)],
                4 => [(1, 4), (2, 8), (3, 12), (4, 16)],
            ],
        )
    end

end

@testset "Full symmetric topology" begin

    fs = FullSymmetric(4)
    @test n_nodes(fs) == n_sources(fs) == n_targets(fs) == 4
    @test n_edges(fs) == 1 + 2 + 3 + 4

    # Forward.
    @test all(check_targets(fs, src, 1:4) for src in 1:4)
    @test all(check_sources(fs, tgt, 1:4) for tgt in 1:4)
    @test all(is_edge(fs, s, t) for s in 1:4 for t in 1:4)
    @test collect(edges(fs)) == [(s, t) for s in 1:4 for t in 1:4]

    # Nested iterators.
    for skip in [true, false], nested in (forward, backward, adjacency) # (indifferent)
        check_nested(
            nested(fs; skip),
            [
                1 => [(1, 1), (2, 2), (3, 4), (4, 7)],
                2 => [(1, 2), (2, 3), (3, 5), (4, 8)],
                3 => [(1, 4), (2, 5), (3, 6), (4, 9)],
                4 => [(1, 7), (2, 8), (3, 9), (4, 10)],
            ],
        )
        # Additional option to only yield lower edges directions
        # so that every edge is only yielded once.
        check_nested(
            adjacency(fs; skip, upper = false),
            [
                1 => [(1, 1)],
                2 => [(1, 2), (2, 3)],
                3 => [(1, 4), (2, 5), (3, 6)],
                4 => [(1, 7), (2, 8), (3, 9), (4, 10)],
            ],
        )
    end

end

end

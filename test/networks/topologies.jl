module TestNetworkTopologies

using Test
using SparseArrays
using EcologicalNetworksDynamics.Networks

function check_targets(top, src, expected)
    actual = collect(target_nodes(top, src))
    @test length(actual) == n_targets(top, src)
    @test expected == actual
end

function check_sources(top, tgt, expected)
    actual = collect(source_nodes(top, tgt))
    @test length(actual) == n_sources(top, tgt)
    @test expected == actual
end

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

        @test n_sources(sr) == n_targets(sr) == 4
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

end

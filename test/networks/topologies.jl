module TestNetworkTopologies

using Test
using SparseArrays
using EcologicalNetworksDynamics.Networks

@testset "Sparse foreign topology" begin

    sf = SparseForeign(sparse([
        0 0 0 1
        0 1 0 0
        0 0 0 0
        0 1 0 1
        1 0 0 1
    ]))

    @test n_sources(sf) == 5
    @test n_targets(sf) == 4
    @test n_edges(sf) == 6

    # Forward.
    tgt(src) = collect(target_nodes(sf, src))
    @test tgt(1) == [4]
    @test tgt(2) == [2]
    @test tgt(3) == []
    @test tgt(4) == [2, 4]
    @test tgt(5) == [1, 4]

    # Bacward.
    src(tgt) = collect(source_nodes(sf, tgt))
    @test src(1) == [5]
    @test src(2) == [2, 4]
    @test src(3) == []
    @test src(4) == [1, 4, 5]

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
    @test [src => collect(targets) for (src, targets) in forward(sf)] == [
        1 => [(4, 1)]
        2 => [(2, 2)]
        4 => [(2, 3), (4, 4)]
        5 => [(1, 5), (4, 6)]
    ]
    @test [src => collect(targets) for (src, targets) in forward(sf; skip = false)] == [
        1 => [(4, 1)]
        2 => [(2, 2)]
        3 => []
        4 => [(2, 3), (4, 4)]
        5 => [(1, 5), (4, 6)]
    ]
    @test [tgt => collect(sources) for (tgt, sources) in backward(sf)] == [
        1 => [(5, 5)]
        2 => [(2, 2), (4, 3)]
        4 => [(1, 1), (4, 4), (5, 6)]
    ]
    @test [tgt => collect(sources) for (tgt, sources) in backward(sf; skip = false)] == [
        1 => [(5, 5)]
        2 => [(2, 2), (4, 3)]
        3 => []
        4 => [(1, 1), (4, 4), (5, 6)]
    ]

end

end

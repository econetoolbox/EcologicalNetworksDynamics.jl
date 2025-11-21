module TestRestrictions

using Test
using EcologicalNetworksDynamics.Networks
using .Networks: Full, Range, Sparse, SparseRanges, restriction_from_mask, indices, toparent
using SparseArrays

@testset "Trivial full restriction." begin

    f = Full(10)
    @test length(f) == 10
    @test 1 in f
    @test 5 in f
    @test 10 in f
    @test collect(indices(f)) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    @test toparent(1, f) == 1
    @test toparent(5, f) == 5
    @test toparent(10, f) == 10

end

@testset "Range restriction." begin

    r = Range(4:8)
    @test length(r) == 5
    @test !(1 in r)
    @test 4 in r
    @test 5 in r
    @test 8 in r
    @test !(9 in r)
    @test !(10 in r)

    exp = 4:8
    @test collect(indices(r)) == exp
    @test toparent.(1:length(r), (r,)) == exp

    function check_mask_to_range(mask, range)
        r = restriction_from_mask(mask)
        @test r == Range(range)
        @test collect(indices(r)) == range
        @test toparent.(1:length(r), (r,)) == range
    end

    check_mask_to_range(Bool[0, 0, 0, 1, 1, 1, 0, 0, 0], 4:6)
    check_mask_to_range(Bool[1, 1, 1, 0, 0, 0], 1:3)
    check_mask_to_range(Bool[0, 0, 0, 1, 1, 1], 4:6)
    check_mask_to_range(Bool[1, 1, 1], 1:3)
    check_mask_to_range(Bool[1, 1, 1], 1:3)

end

@testset "Sparse restriction." begin

    s = Sparse([1, 3, 5, 6, 8])
    @test length(s) == 5
    @test 1 in s
    @test !(2 in s)
    @test 3 in s
    @test !(4 in s)
    @test 6 in s
    @test !(7 in s)
    @test 8 in s
    @test !(9 in s)
    @test !(10 in s)

    exp = [1, 3, 5, 6, 8]
    @test collect(indices(s)) == exp
    @test toparent.(1:length(s), (s,)) == exp

    function check_mask_to_sparse(mask, sparse)
        s = restriction_from_mask(mask)
        @test s == Sparse(sparse)
        @test collect(indices(s)) == sparse
        @test toparent.(1:length(s), (s,)) == sparse
    end

    check_mask_to_sparse(Bool[0, 1, 1, 0, 1, 0, 1], [2, 3, 5, 7])
    check_mask_to_sparse(Bool[1, 1, 1, 0, 1, 0, 0], [1, 2, 3, 5])
    check_mask_to_sparse(Bool[0, 0, 0], [])
    check_mask_to_sparse(Bool[], [])

end

@testset "Sparse ranges restriction." begin

    s = SparseRanges([2:6, 8:9, 12:15])
    @test length(s) == 11 #                 1  2  3  4  5     6  7        8  9 10 11
    @test [i in s for i in 1:15] == Bool[0, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1]
    #                                    1  2  3  4  5  6  7  8  9 10 11 12 13 14 15

    exp = [2, 3, 4, 5, 6, 8, 9, 12, 13, 14, 15]
    @test collect(indices(s)) == exp
    @test toparent.(1:length(s), (s,)) == exp

    f = restriction_from_mask(Bool[0, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1])
    @test f isa SparseRanges
    @test f == s

    function check_mask_to_sparse_ranges(mask, ranges, inds)
        s = restriction_from_mask(mask)
        @test s == SparseRanges(ranges)
        @test collect(indices(s)) == inds
        @test toparent.(1:length(s), (s,)) == inds
    end

    check_mask_to_sparse_ranges(
        Bool[1, 1, 1, 1, 0, 1, 1, 1, 1],
        [1:4, 6:9],
        [1, 2, 3, 4, 6, 7, 8, 9],
    )

    check_mask_to_sparse_ranges(
        Bool[1, 1, 1, 0, 1, 1, 1, 1, 0],
        [1:3, 5:8],
        [1, 2, 3, 5, 6, 7, 8],
    )

    check_mask_to_sparse_ranges(
        Bool[0, 1, 1, 0, 1, 1, 1, 1, 1],
        [2:3, 5:9],
        [2, 3, 5, 6, 7, 8, 9],
    )

end

@testset "Expand data from restrictions" begin

    @test expand(Range(3:5), 8, [3, 2, 1]) == sparse([0, 0, 3, 2, 1, 0, 0, 0])

    @test expand(Sparse([2, 4, 8, 9]), 10, [4, 3, 2, 1]) ==
          sparse([0, 4, 0, 3, 0, 0, 0, 2, 1, 0])

    @test expand(SparseRanges([2:5, 7:8]), 10, [6, 5, 4, 3, 2, 1]) ==
          sparse([0, 6, 5, 4, 3, 0, 2, 1, 0, 0])

end

end

module TestRestrictions

using Test
using EcologicalNetworksDynamics.Networks
using .Networks: Full, Range, Sparse, sparse_from_mask, indices, toparent

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
    @test collect(indices(r)) == [4, 5, 6, 7, 8]
    @test toparent(1, r) == 4
    @test toparent(2, r) == 5
    @test toparent(3, r) == 6
    @test toparent(4, r) == 7
    @test toparent(5, r) == 8

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
    @test collect(indices(s)) == [1, 3, 5, 6, 8]
    @test toparent(1, s) == 1
    @test toparent(2, s) == 3
    @test toparent(3, s) == 5
    @test toparent(4, s) == 6
    @test toparent(5, s) == 8

    s = sparse_from_mask(Bool[0, 1, 1, 0, 1, 0, 1])
    @test collect(indices(s)) == [2, 3, 5, 7]

end

end

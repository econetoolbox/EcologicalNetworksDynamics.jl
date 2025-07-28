module TestNodes

using Test
using SparseArrays
using OrderedCollections
using Main.TestUtils
using EcologicalNetworksDynamics.Networks

@testset "Nodes classes hierarchy." begin

    n = Network()
    add_class!(n, :species, "abcde")

    @test is_disp(n, strip("""
             Network with 5 nodes and 0 field:
               Nodes:
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
             """))


    add_field!(n, :species, :biomass, zeros(5))
    add_field!(n, :species, :mortality, collect(1:5) ./ 10)
    @test is_disp(n, strip("""
             Network with 5 nodes and 2 fields:
               Nodes:
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_subclass!(n, :species, :producers, Bool[0, 1, 1, 0, 1])
    @test is_disp(n, strip("""
             Network with 5 nodes and 2 fields:
               Nodes:
                 producers (3): [:b, :c, :e]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_field!(n, :producers, :growth, [0.15, 0.25, 0.35])
    @test is_disp(n, strip("""
             Network with 5 nodes and 3 fields:
               Nodes:
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_class!(n, :nutrients, "uvw")
    @test is_disp(n, strip("""
             Network with 8 nodes and 3 fields:
               Nodes:
                 nutrients (3): [:u, :v, :w]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_field!(n, :nutrients, :turnover, [4, 5, 6])
    @test is_disp(n, strip("""
             Network with 8 nodes and 4 fields:
               Nodes:
                 nutrients (3): [:u, :v, :w]
                   turnover: [4, 5, 6]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_subclass!(n, :producers, :mineral_bound, Bool[1, 0, 1])
    @test is_disp(n, strip("""
             Network with 8 nodes and 4 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                 nutrients (3): [:u, :v, :w]
                   turnover: [4, 5, 6]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    add_field!(n, :mineral_bound, :consumption_rate, [10, 50])
    @test is_disp(n, strip("""
             Network with 8 nodes and 5 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                   consumption_rate: [10, 50]
                 nutrients (3): [:u, :v, :w]
                   turnover: [4, 5, 6]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   biomass: [0.0, 0.0, 0.0, 0.0, 0.0]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

end

@testset "Nodes views." begin

    n = Network()
    add_class!(n, :species, "abcde")
    add_field!(n, :species, :mortality, collect(1:5) ./ 10)
    add_subclass!(n, :species, :producers, Bool[0, 1, 1, 0, 1])
    add_field!(n, :producers, :growth, [0.15, 0.25, 0.35])
    add_subclass!(n, :producers, :mineral_bound, Bool[1, 0, 1])
    add_field!(n, :mineral_bound, :consumption_rate, [10, 50])
    @test is_disp(n, strip("""
             Network with 5 nodes and 3 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                   consumption_rate: [10, 50]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))
    # Fork to check later COW.
    f = copy(n)

    # View into base class node data.
    m = nodes_view(n, :species, :mortality)
    @test is_repr(m, "NodesView'2([0.1, 0.2, 0.3, 0.4, 0.5])")

    # Index view.
    @test m[:a] == m[1] == 0.1
    @test m[:b] == m[2] == 0.2
    @test m[:e] == m[5] == 0.5

    # Mutate.
    m[:a] *= 10
    m[2] *= 5
    m[:e] *= -1
    @test is_repr(m, "NodesView([1.0, 1.0, 0.3, 0.4, -0.5])")

    # View into subclass node data.
    c = nodes_view(n, :mineral_bound, :consumption_rate)
    @test is_repr(c, "NodesView'2([10, 50])")

    c[1:2] ./= 10
    c[:e] *= 2

    @test is_repr(c, "NodesView([1, 10])")

    # Also works with broacasting.
    c[1:2] .*= 2
    @test is_repr(c, "NodesView([2, 20])")

    # Check COW aliasing/mutation.
    @test is_disp(n, strip("""
             Network with 5 nodes and 3 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                   consumption_rate: [2, 20]
                 producers (3): [:b, :c, :e]
                   growth'2: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   mortality: [1.0, 1.0, 0.3, 0.4, -0.5]
             """))
    @test is_disp(f, strip("""
             Network with 5 nodes and 3 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                   consumption_rate: [10, 50]
                 producers (3): [:b, :c, :e]
                   growth'2: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

end

@testset "Nodes exports." begin

    n = Network()
    add_class!(n, :species, "abcde")
    add_field!(n, :species, :mortality, collect(1:5) ./ 10)
    add_subclass!(n, :species, :producers, Bool[0, 1, 1, 0, 1])
    add_field!(n, :producers, :growth, [0.15, 0.25, 0.35])
    add_subclass!(n, :producers, :mineral_bound, Bool[1, 0, 1])
    add_field!(n, :mineral_bound, :consumption_rate, [10, 50])
    @test is_disp(n, strip("""
             Network with 5 nodes and 3 fields:
               Nodes:
                 mineral_bound (2): [:b, :e]
                   consumption_rate: [10, 50]
                 producers (3): [:b, :c, :e]
                   growth: [0.15, 0.25, 0.35]
                 root: <no data>
                 species (5): [:a, :b, :c, :d, :e]
                   mortality: [0.1, 0.2, 0.3, 0.4, 0.5]
             """))

    # Exports within root parent class.
    g = nodes_view(n, :producers, :growth)

    v = to_vec(g)
    @test typeof(v) === Vector{Float64}
    @test v == [0.15, 0.25, 0.35]

    s = to_sparse(g)
    @test typeof(s) === SparseVector{Float64,Int}
    @test s == sparse([0, 0.15, 0.25, 0, 0.35])

    m = to_map(g)
    @test typeof(m) === OrderedDict{Symbol,Float64}
    @test m == OrderedDict(:b => 0.15, :c => 0.25, :e => 0.35)

    # Exports within non-root parent class.
    r = nodes_view(n, :mineral_bound, :consumption_rate)

    v = to_vec(r)
    @test typeof(v) === Vector{Int}
    @test v == [10, 50]

    s = to_sparse(r)
    @test typeof(s) === SparseVector{Int,Int}
    @test s == sparse([10, 0, 50])

    m = to_map(r)
    @test typeof(m) === OrderedDict{Symbol,Int}
    @test m == OrderedDict(:b => 10, :e => 50)

    # Export several parents at once.
    s = to_sparse(r, :root)
    @test typeof(s) === SparseVector{Int,Int}
    @test s == sparse([0, 10, 0, 0, 50])

end

end

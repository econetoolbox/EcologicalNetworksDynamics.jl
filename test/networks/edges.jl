module TestEdges

using Test
using SparseArrays
using OrderedCollections
using Main.TestUtils
import Main: @netfails
using EcologicalNetworksDynamics.Networks
const N = Networks

@testset "Setting webs and data." begin

    n = Network()
    add_class!(n, :species, "abcde")
    add_class!(n, :nutrients, "uvw")
    f = copy(n)

    #---------------------------------------------------------------------------------------
    # SparseForeign.
    m = sparse([
        0 0 4 0 9
        0 3 5 0 8
        1 0 7 2 0
    ])
    flow = SparseForeign(m)
    add_web!(n, :flow, (:nutrients, :species), flow)
    @test is_disp(n, strip("""
    Network with 8 nodes and 8 edges:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        flow: nutrients => species (8, sparse)
    """))

    v = edges_vec(flow, m)
    add_field!(n, :flow, :intensity, v)
    @test is_disp(n, strip("""
    Network with 8 nodes, 8 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        flow: nutrients => species (8, sparse)
          intensity: [4, 9, 3, 5, 8, 1, 7, 2]
    """))

    @netfails(
        add_web!(n, :reverse, (:species, :nutrient), flow),
        "Nodes in class :species: 5, but 3 in topology sources."
    )
    @netfails(
        add_field!(n, :flow, :too_small, [1, 2, 3]),
        "The given vector (size 3) does not match the :flow web size (8)."
    )

    #---------------------------------------------------------------------------------------
    # SparseReflexive.
    m = sparse([
        0 4 5
        0 0 1
        2 0 0
    ])
    conv = SparseReflexive(m)
    add_web!(n, :convert, (:nutrients, :nutrients), conv)
    add_field!(n, :convert, :intensity, edges_vec(conv, m))
    @test is_disp(n, strip("""
    Network with 8 nodes, 12 edges and 2 fields:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        convert: nutrients => nutrients (4, sparse)
          intensity: [4, 5, 1, 2]
        flow: nutrients => species (8, sparse)
          intensity: [4, 9, 3, 5, 8, 1, 7, 2]
    """))

    #---------------------------------------------------------------------------------------
    # SparseSymmetric.
    m = sparse([ # Upper triangle ignored.
        0 9 9 9 9
        0 5 9 9 9
        4 0 6 9 9
        0 0 2 1 9
        0 8 0 3 0
    ])
    comp = SparseSymmetric(m)
    add_web!(n, :compete, (:species, :species), comp)
    add_field!(n, :compete, :intensity, edges_vec(comp, m))
    @test is_disp(n, strip("""
    Network with 8 nodes, 19 edges and 3 fields:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        compete: species => species (7, symmetric, sparse)
          intensity: [5, 4, 6, 2, 1, 8, 3]
        convert: nutrients => nutrients (4, sparse)
          intensity: [4, 5, 1, 2]
        flow: nutrients => species (8, sparse)
          intensity: [4, 9, 3, 5, 8, 1, 7, 2]
    """))

    #---------------------------------------------------------------------------------------
    # FullForeign.
    n = copy(f) # Reset from now on to not clutter test file.
    m = [
        1 3 1
        2 4 2
        8 5 5
        6 6 4
        0 7 5
    ]
    aff = FullForeign(m)
    add_web!(n, :affinity, (:species, :nutrients), aff)
    add_field!(n, :affinity, :value, edges_vec(aff, m))
    @test is_disp(n, strip("""
    Network with 8 nodes, 15 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        affinity: species => nutrients (15, full)
          value: [1, 3, 1, 2, 4, 2, 8, 5, 5, 6, 6, 4, 0, 7, 5]
    """))

    #---------------------------------------------------------------------------------------
    # FullReflexive.
    n = copy(f)
    m = [
        1 3 1
        2 4 2
        8 5 5
    ]
    paths = FullReflexive(m)
    add_web!(n, :trade, (:nutrients, :nutrients), paths)
    add_field!(n, :trade, :rate, edges_vec(paths, m))
    @test is_disp(n, strip("""
    Network with 8 nodes, 9 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        trade: nutrients => nutrients (9, full)
          rate: [1, 3, 1, 2, 4, 2, 8, 5, 5]
    """))

    #---------------------------------------------------------------------------------------
    # FullSymmetric.
    n = copy(f)
    m = [
        1 9 9
        2 4 9
        8 5 5
    ]
    paths = FullSymmetric(m)
    add_web!(n, :paths, (:nutrients, :nutrients), paths)
    add_field!(n, :paths, :distance, edges_vec(paths, m))
    @test is_disp(n, strip("""
    Network with 8 nodes, 6 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        paths: nutrients => nutrients (6, symmetric, full)
          distance: [1, 2, 4, 8, 5, 5]
    """))

end

@testset "Edges Views" begin

    n = Network()
    add_class!(n, :species, "abcde")
    add_class!(n, :nutrients, "uvw")

    m = sparse([
        0 9 9 9 9
        0 5 9 9 9
        4 0 6 9 9
        0 0 2 1 9
        0 8 0 3 0
    ])
    comp = SparseSymmetric(m)
    add_web!(n, :compete, (:species, :species), comp)
    add_field!(n, :compete, :intensity, edges_vec(comp, m))

    @test is_disp(n, strip("""
    Network with 8 nodes, 7 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        compete: species => species (7, symmetric, sparse)
          intensity: [5, 4, 6, 2, 1, 8, 3]
    """))
    f = copy(n)

    # View into base web node data.
    c = edges_view(n, :compete, :intensity)
    @test is_repr(c, "EdgesView'2([5, 4, 6, 2, 1, 8, 3])")

    # Index view.
    @test c[1] == c[(2, 2)] == c[(:b, :b)] == 5
    @test c[4] == c[(4, 3)] == c[(:d, :c)] == 2
    @test c[end] == c[(5, 4)] == c[(:e, :d)] == 3

    # Symmetry reflected.
    @test c[(4, 3)] == c[(3, 4)]
    @test c[(2, 5)] == c[(5, 2)]

    # Can't index outside topology.
    @netfails(c[(9, 2)], "Not an index for :compete web with 5 sources: 9.")
    @netfails(c[(1, 2)], "Not an edge in :compete web: (1, 2).")
    @netfails(c[(:a, :b)], "Not an edge in :compete web: (:a, :b).")

    # Mutate.
    c[1] *= 2
    c[(4, 3)] += 2
    c[(:e, :d)] -= 2

    @test is_repr(c, "EdgesView([10, 4, 6, 4, 1, 8, 1])")

    # Check COW aliasing/mutation.
    @test is_disp(n, strip("""
    Network with 8 nodes, 7 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        compete: species => species (7, symmetric, sparse)
          intensity: [10, 4, 6, 4, 1, 8, 1]
    """))
    @test is_disp(f, strip("""
    Network with 8 nodes, 7 edges and 1 field:
      Nodes:
        nutrients (3): [:u, :v, :w]
        species (5): [:a, :b, :c, :d, :e]
      Edges:
        compete: species => species (7, symmetric, sparse)
          intensity: [5, 4, 6, 2, 1, 8, 3]
    """))

end

@testset "Edges exports" begin

    n = Network()
    add_class!(n, :species, "abcde")
    add_class!(n, :nutrients, "uvw")
    m = sparse([
        0 9 9 9 9
        0 5 9 9 9
        4 0 6 9 9
        0 0 2 1 9
        0 8 0 3 0
    ])
    comp = SparseSymmetric(m)
    add_web!(n, :compete, (:species, :species), comp)
    add_field!(n, :compete, :intensity, edges_vec(comp, m))
    c = edges_view(n, :compete, :intensity)

    v = to_vec(c)
    @test typeof(v) === Vector{Int}
    @test v == [5, 4, 6, 2, 1, 8, 3]

    m = to_dense(c)
    @test typeof(m) === Matrix{Int}
    @test m == [ # Symmetry worked ;)
        0 0 4 0 0
        0 5 0 0 8
        4 0 6 2 0
        0 0 2 1 3
        0 8 0 3 0
    ]

    m = to_sparse(c)
    @test typeof(m) === N.SparseMatrix{Int}
    @test m == sparse([
        0 0 4 0 0
        0 5 0 0 8
        4 0 6 2 0
        0 0 2 1 3
        0 8 0 3 0
    ])

end

end

"""
Test all aspects of typical Web component, using foodweb as an example.
"""
module WebTest

using EcologicalNetworksDynamics
using SparseArrays

using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @test_err, @bpfails, addfails, @propfails, @immutfails
using EcologicalNetworksDynamics.NetworkFramework:
    EN, D, F, NF, Network, Views, SparseMatrix
using EcologicalNetworksDynamics.Framework: @PropertySpace

const d, _D = D.Web(:trophic)
const Tr = @PropertySpace(trophic, Network)
using Test

@testset "Web component: blueprints" begin

    @test_disp(
        Foodweb,
        """
        Foodweb (component for $Network, expandable from:
          Matrix: boolean matrix of foodweb links,
          Adjacency: adjacency list of foodweb links,
        )\
        """,
    )

    # ======================================================================================
    # From a matrix.

    A = Bool[
        0 0 1
        1 0 1
        0 0 0
    ]

    #---------------------------------------------------------------------------------------
    # Construct.

    # Various input types.
    bp = Foodweb.Matrix(A)
    @test bp == Foodweb.Matrix(Int.(A))
    @test bp == Foodweb.Matrix(BitMatrix(A))
    # Implicit constructor.
    @test bp == Foodweb(A)
    @test bp == Foodweb(Int.(A))
    @test bp == Foodweb(BitMatrix(A))
    @test bp == Foodweb(sparse(A))
    @test bp == Foodweb(sparse(Int.(A)))
    @test bp == Foodweb(sparse(BitMatrix(A)))
    @test_repr(bp, "<Foodweb>:Matrix(A: 3×3:3 (true))")
    @test_disp(
        bp,
        """
        blueprint for <Foodweb>: Matrix {
          A: 3×3 sparse matrix with 3 values (true),
        }\
        """,
    )

    # Alias.
    input = sparse(A)
    bp = Foodweb(input)
    @test bp.A === input

    @bpfails(Foodweb.Matrix(:a),
        Foodweb.Matrix, :construct,
        (nothing, :whole, :convert, SparseMatrix{Bool}, :a, "Conversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(Foodweb(zeros(Bool, 2, 3)),
        Foodweb.Matrix, :construct,
        (nothing, :whole, :check, spzeros(Bool, (2, 3)),
            "The adjacency matrix of size (3, 2) is not squared."))

    #---------------------------------------------------------------------------------------
    # Late check.

    m = Model(Species(3))
    addfails.@check(m + Foodweb(zeros(Bool, 2, 2)), [],
        (Foodweb.Matrix, :late,
            (:whole, :whole, :check, spzeros(Bool, 2, 2),
                "There are 3 :species nodes but the provided matrix is of size (2, 2).")))
    @test_err(m + Foodweb(zeros(Bool, 2, 2)), # First time with a :late error.
        """
        Blueprint cannot expand against current system value:
        While verifying blueprint against model:
        There are 3 :species nodes but the provided matrix is of size (2, 2).
        Received: sparse(Int64[], Int64[], Bool[], 2, 2) ::$(SparseMatrix{Bool})
        Not all blueprints have been expanded.
        This means that the system consistency is still guaranteed, \
        but some components have not been added.
        in Foodweb.Matrix\
        """)

    #---------------------------------------------------------------------------------------
    # Expand, implying underlying class.

    m = Model(bp)
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test_disp(m,
        """
        Model (alias for $(F.System){$Network}) with 2 components:
          - Species: 3 (:s1, :s2, :s3)
          - Foodweb: 3 links, 1 producer, 2 consumers, 2 preys, 1 top.\
        """)

    # ======================================================================================
    # From an adjacency list.

    #---------------------------------------------------------------------------------------
    # Construct.

    A = [:a => (:b, :c), (:b, :d) => :e] # Using labels.
    Ai = [6 => (4, 2), (4, 1) => 3] # Using indices (with a different topology).

    bp = Foodweb.Adjacency(A)
    bpi = Foodweb.Adjacency(Ai)
    @test bp == Foodweb.Adjacency(['a' => ["b", "c"], ['b', :d] => "e"])
    @test bpi == Foodweb.Adjacency(Iterators.map(identity, [6 => [4, 2], ([4, 1], 3)]))
    # Implicit constructor.
    @test bp == Foodweb(A)
    @test bpi == Foodweb(Ai)
    @test bp == Foodweb(['a' => ["b", "c"], ['b', :d] => "e"])
    @test bpi == Foodweb(Iterators.map(identity, [6 => [4, 2], ([4, 1], 3)]))
    @test_repr(bp, "<Foodweb>:Adjacency(A: {a: {b, c}, b: {e}, d: {e}})")
    @test_repr(bpi, "<Foodweb>:Adjacency(A: {6: {4, 2}, 4: {3}, 1: {3}})")
    @test_disp(bp,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {
            a -> { b, c },
            b -> { e },
            d -> { e },
          },
        }\
        """)
    @test_disp(bpi,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {
            6 -> { 4, 2 },
            4 -> { 3 },
            1 -> { 3 },
          },
        }\
        """)

    # Alias.
    for input in (bp.A, bpi.A)
        bp = Foodweb(input)
        @test bp.A === input
    end

    @bpfails(Foodweb.Adjacency(:a),
        Foodweb.Adjacency, :construct,
        (nothing, :whole, :list,
            "Input for binary adjacency map needs to be iterable.\n\
             Received: :a  ::$Symbol."))
    @test_err(Foodweb.Adjacency(:a), # First test with :list.
        """
        While constructing blueprint Foodweb.Adjacency:
        Input for binary adjacency map needs to be iterable.
        Received: :a  ::Symbol.\
        """
    )

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("axy"), Foodweb(A)), [],
        (Foodweb.Adjacency, :late,
            (:whole, :whole, :check, :b, "Not a target label among :species.")))
    addfails.@check(Model(Species("xyz"), Foodweb(Ai)), [],
        (Foodweb.Adjacency, :late,
            (:whole, :whole, :check, 6, "Not a valid source :species index among 3 nodes."),
        ))

    #---------------------------------------------------------------------------------------
    # Expand, implying underlying class.

    m = Model(Foodweb(A))
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test m.species.names == [:a, :b, :c, :e, :d]
    # TODO: the ordering obtained above is unexpected: fix.
    # This is because in general `(a, b) => c` gets parsed as `a => c, b => c`
    # thus reverting the order.
    # The fix would be that the parsing should also produce an ordered list of labels
    # but there is nowhere to store that list within the blueprint yet. (Re)Consider?

    m = Model(Foodweb(Ai))
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test m.species.names == [:s1, :s2, :s3, :s4, :s5, :s6]

end

@testset "Web component: properties" begin

    @propfails(Model().trophic.matrix,
        Tr, :matrix, "Component <Foodweb> is required to read this property.")

    m = Model(Species("abcde"), Foodweb([:a => (:b, :c), (:b, :d) => (:c, :e)]))

    # Number of edges in the web.
    @test m.trophic.n_links == m.trophic.n_edges == 6
    # Topology as a matrix.
    @test m.trophic.matrix == m.trophic.mask ==
          [
              0 1 1 0 0
              0 0 1 0 1
              0 0 0 0 0
              0 0 1 0 1
              0 0 0 0 0
          ]

    # Types.
    @test m.trophic.n_links isa Int
    @test m.trophic.n_edges isa Int
    @test m.trophic.matrix isa Views.EdgeMaskView{d}
    @test m.trophic.mask isa Views.EdgeMaskView{d}

    # Edges iterators.
    c = collect
    mc(it) = map(((src, sub),) -> (src, collect(sub)), it)

    # Flat:
    @test c(m.trophic.iter.edges) == c(m.trophic.iter.label.edges) ==
          [(:a, :b), (:a, :c), (:b, :c), (:d, :c), (:b, :e), (:d, :e)]
    #       1         2         3         4         5         6
    # Nested, forward (source-first).
    @test mc(m.trophic.iter.forward) == mc(m.trophic.iter.label.forward) ==
          [
              (:a, [(:b, 1), (:c, 2)]),
              (:b, [(:c, 3), (:e, 5)]),
              (:c, []),
              (:d, [(:c, 4), (:e, 6)]),
              (:e, []),
          ]
    # Nested, backward (target-first).
    @test mc(m.trophic.iter.backward) == mc(m.trophic.iter.label.backward) ==
          [
              (:a, []),
              (:b, [(:a, 1)]),
              (:c, [(:a, 2), (:b, 3), (:d, 4)]),
              (:d, []),
              (:e, [(:b, 5), (:d, 6)]),
          ]
    # Transposed variant.
    @test c(m.trophic.iter.edges_transposed) == c(m.trophic.iter.label.edges_transposed) ==
          [(:a, :b), (:a, :c), (:b, :c), (:b, :e), (:d, :c), (:d, :e)]
    # Skip variants.
    @test mc(m.trophic.iter.forward_skip) == mc(m.trophic.iter.label.forward_skip) ==
          [
              (:a, [(:b, 1), (:c, 2)]),
              (:b, [(:c, 3), (:e, 5)]),
              (:d, [(:c, 4), (:e, 6)]),
          ]
    @test mc(m.trophic.iter.backward_skip) == mc(m.trophic.iter.label.backward_skip) ==
          [
              (:b, [(:a, 1)]),
              (:c, [(:a, 2), (:b, 3), (:d, 4)]),
              (:e, [(:b, 5), (:d, 6)]),
          ]

    # Index versions.                        1       2       3       4       5       6
    @test c(m.trophic.iter.index.edges) == [(1, 2), (1, 3), (2, 3), (4, 3), (2, 5), (4, 5)]
    @test mc(m.trophic.iter.index.forward) == [
        (1, [(2, 1), (3, 2)]),
        (2, [(3, 3), (5, 5)]),
        (3, []),
        (4, [(3, 4), (5, 6)]),
        (5, []),
    ]
    @test mc(m.trophic.iter.index.backward) == [
        (1, []),
        (2, [(1, 1)]),
        (3, [(1, 2), (2, 3), (4, 4)]),
        (4, []),
        (5, [(2, 5), (4, 6)]),
    ]
    @test c(m.trophic.iter.index.edges_transposed) ==
          [(1, 2), (1, 3), (2, 3), (2, 5), (4, 3), (4, 5)]
    @test mc(m.trophic.iter.index.forward_skip) == [
        (1, [(2, 1), (3, 2)]),
        (2, [(3, 3), (5, 5)]),
        (4, [(3, 4), (5, 6)]),
    ]
    @test mc(m.trophic.iter.index.backward_skip) == [
        (2, [(1, 1)]),
        (3, [(1, 2), (2, 3), (4, 4)]),
        (5, [(2, 5), (4, 6)]),
    ]

end

@testset "Web component: mask view" begin

    View = Views.EdgeMaskView{d}

    m = Model(Species("abcde"), Foodweb([:a => (:b, :c), (:b, :d) => (:c, :e)]))
    v = m.trophic.mask

    @test_repr(v, "<trophic>(5×5: 6 edges)")
    @test_disp(v,
        """
        EdgesMaskView<trophic>{Bool} (5×5: 6 edges)
         · 1 1 · ·
         · · 1 · 1
         · · · · ·
         · · 1 · 1
         · · · · ·\
        """
    )

    # The view has some basic matrix-like interface.
    A = sparse([
        0 1 1 0 0
        0 0 1 0 1
        0 0 0 0 0
        0 0 1 0 1
        0 0 0 0 0
    ])
    @test v == collect(v) == [i for i in v] == A
    # The view may be extracted into a regular sparse matrix.
    e = extract(v)
    @test e isa SparseMatrix{Bool}
    @test e == v == A

    # Either index with integers or labels, also converted data input.
    @test v[1, 1] == false
    @test v[0x1, 0x2] == true
    @test v[:a, :c] == true
    @test v['a', "d"] == false
    # HERE: test boolean masks now.

    # ======================================================================================
    # ↑ ↑ HERE updating tests ↑ ↑
    # ======================================================================================

    # Index with either integers or labels.
    @test v[1, 1] == false
    @test v[1, 2] == true
    @test v[:a, :a] == false
    @test v[:a, :b] == true
    @test v[1:2, 2:3] == [1 1; 0 0]
    @test v[2:end, (end-1):end] == [0 0; 1 0]

    # Immutable.
    @immutfails((v[1, 1] = true), immut)
    @immutfails((v[:a, :b] = false), immut)
    @immutfails((v[1:2, 2:end] = false), immut)
    # This takes priority over indexing semantics.
    @immutfails((v[] = true), immut)
    @immutfails((v[1, 2, 3] = true), immut)
    @immutfails((v[nothing] = true), immut)
    @immutfails((v[nothing, 1] = true), immut)
    @immutfails((v[1, nothing] = true), immut)

    # But the *blueprint* can be mutated.
    bp.A[1, 1] = true
    @test Model(bp).foodweb.mask == [1 1 1; 1 0 0; 1 1 0]

    # Alias to the value inside the blueprint if exact type match.
    input = sparse(Bool[0 0; 0 0])
    bp = Foodweb(input)
    @test bp.A === input
    input[1, 2] = 1
    @test bp.A == [0 1; 0 0]

    # Fail construct from matrix.
    @bpfails(Model(Foodweb([1 0 1; 0 1 0])),
        early, [Foodweb.Matrix],
        "The adjacency matrix of size (3, 2) is not squared.\n\
         Received: 2×3 SparseMatrixCSC{Bool, $Int} with 3 stored entries:\n \
          1  ⋅  1\n \
          ⋅  1  ⋅")
    @bpfails(Model(Species(3), Foodweb([0 1; 0 0])),
        late, [Foodweb.Matrix],
        "There are 3 :species nodes but the provided matrix is of size (2, 2).\n\
         Received: 2×2 SparseMatrixCSC{Bool, $Int} with 1 stored entry:\n \
          ⋅  1\n \
          ⋅  ⋅")

    # Construct from adjacency matrix.
    A = [:a => (:b, :c), (:d, :c) => (:b, :e)]
    bp = Foodweb.Adjacency(A)
    @test bp == Foodweb(A) # Directly dispatched from component.
    @test is_repr(bp, "<Foodweb>:Adjacency(A: {a: {b, c}, d: {b, e}, c: {b, e}})")
    @test is_disp(
        bp,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {a: {b, c}, d: {b, e}, c: {b, e}},
        }\
        """,
    )
    # All list parsing errors are available here.
    @bpfails(Foodweb.Adjacency([:a => :b => :c]),
        "The pair at [1][right] \
         is just considered an iterable in this context, which may be confusing. \
         Consider grouping with an explicit vector instead like [:b, :c].")
    m = Model(bp)
    @test m.species.names == [:a, :b, :c, :d, :e]
    @test m.trophic.matrix == [
        0 1 1 0 0
        0 0 0 0 0
        0 1 0 0 1
        0 1 0 0 1
        0 0 0 0 0
    ]

    # Same with only indices instead.
    A = [1 => (2, 3), (4, 3) => (2, 5)]
    bp = Foodweb.Adjacency(A)
    @test bp == Foodweb(A) # Directly dispatched from component.
    @test is_repr(bp, "<Foodweb>:Adjacency(A: {1: {2, 3}, 4: {2, 5}, 3: {2, 5}})")
    @test is_disp(
        bp,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {1: {2, 3}, 4: {2, 5}, 3: {2, 5}},
        }\
        """,
    )
    @bpfails(Foodweb.Adjacency([1 => (2, 2)]),
        "Duplicated target node reference at [1][right][2]: 2 ::$Int.")
    m = Model(bp)
    @test m.species.names == [:s1, :s2, :s3, :s4, :s5]
    @test m.trophic.mask ==
          m.trophic.matrix ==
          [
              0 1 1 0 0
              0 0 0 0 0
              0 1 0 0 1
              0 1 0 0 1
              0 0 0 0 0
          ]

    # Interpolate identifiers if some are missing.
    @test Model(Foodweb([5 => 3, 6 => 8])).trophic.matrix == [
        0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0
        0 0 1 0 0 0 0 0
        0 0 0 0 0 0 0 1
        0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0
    ]

    # Generic construct failure.
    @bpfails(Foodweb([1 => 2 0 1]),
        "Cannot convert input to either:\n  \
           - $(SparseMatrix{Bool})\n  \
           - $(EN.BinAdjacency)",
        [1 => 2 0 1])

end

end

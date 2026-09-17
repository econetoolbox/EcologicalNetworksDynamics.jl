"""
Test all aspects of typical Web component, using foodweb as an example.
"""
module WebTest

using EcologicalNetworksDynamics
using SparseArrays

import EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @bpfails, @propfails, @immutfails
import EcologicalNetworksDynamics.NetworkFramework: EN, D, Network, Views, SparseMatrix

const d, _D = D.Web(:trophic)
const View = Views.EdgeMaskView{d}
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
        0 1 1
        1 0 0
        1 1 0
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
    @test_repr(bp, "<Foodweb>:Matrix(A: 3×3:5 (true))")
    @test_disp(
        bp,
        """
        blueprint for <Foodweb>: Matrix {
          A: 3×3 sparse matrix with 5 values (true),
        }\
        """,
    )

    # Alias.
    input = sparse(A)
    bp = Foodweb(input)
    @test bp.A === input

    @bpfails(Foodweb.Matrix(:a),
        Foodweb.Matrix, :construct, nothing,
        (nothing, :whole, :convert, SparseMatrix{Bool}, :a, "Conversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(Foodweb(zeros(Bool, 2, 3)),
        Foodweb.Matrix, :construct, nothing,
        (nothing, :whole, :check, spzeros(Bool, (2, 3)),
            "The adjacency matrix of size (3, 2) is not squared."))

    # ======================================================================================
    # ↑ ↑ HERE updating tests ↑ ↑
    # ======================================================================================

    # Expand into a web component.
    m = Model(Species("abc"), bp)
    @test m.trophic.n_edges == m.trophic.n_links == 5

    # The adjacence property becomes available as a view.
    v = m.foodweb.mask
    @test v isa View
    @test v isa AbstractMatrix{Bool}
    @test is_repr(v, "<trophic>(3×3: 5 edges)")
    @test is_disp(
        v,
        """
        EdgeMaskView<trophic>{Bool} (3×3: 5 edges)
         · 1 1
         1 · ·
         1 1 ·\
        """,
    )
    @propfails(
        Model().foodweb.mask,
        Tr, trophic.mask, # (alias)
        "Component <Foodweb> is required to read this property."
    )

    # The view has some basic matrix-like interface.
    @test v == collect(v) == A == [i for i in v]

    # The view may be extracted into a regular sparse matrix.
    e = extract(v)
    @test e isa SparseMatrix{Bool}
    @test e == v

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

"""
Test all aspects of typical Web component,
using Foodweb as an example, but without testing anything specific to the foodweb.
Anything specific to foodweb will be tested in a dedicated file.
"""
module WebTest

# What the end user should have to import.
using EcologicalNetworksDynamics
using SparseArrays

# Additional imports only used here for testing purpose.
using Test
import EcologicalNetworksDynamics: EN, Network, Views, Web, SparseMatrix
import Main: is_repr, is_disp, @viewfails, @inputfails, @sysfails, Value
const View = Views.EdgesMaskView{Web(:trophic)} # Tested view type.

@testset "Typical Web component" begin

    # Blueprints available from component.
    @test Foodweb isa EN.Component
    @test is_repr(Foodweb, "Foodweb")
    @test is_disp(
        Foodweb,
        """
        Foodweb (component for $Network, expandable from:
          Matrix: boolean matrix of foodweb links,
          Adjacency: adjacency list of foodweb links,
        )\
        """,
    )
    @test Foodweb.Matrix <: EN.Blueprint
    @test Foodweb.Adjacency <: EN.Blueprint

    # Construct from a matrix, converted from various input types.
    A = Bool[
        0 1 1
        1 0 0
        1 1 0
    ]
    bp = Foodweb.Matrix(A)
    Ai = Int[0 1 1; 1 0 0; 1 1 0]
    @test bp == Foodweb.Matrix(Ai)
    # Implicit constructor.
    @test bp == Foodweb(A)
    @test bp == Foodweb(Ai)
    @test is_repr(bp, "<Foodweb>:Matrix(A: 3×3:5 (true))")
    @test is_disp(
        bp,
        """
        blueprint for <Foodweb>: Matrix {
          A: 3×3 sparse matrix with 5 values (true),
        }\
        """,
    )

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
        EdgesMaskView<trophic>{Bool} (3×3: 5 edges)
         · 1 1
         1 · ·
         1 1 ·\
        """,
    )
    @sysfails( # Unless the component is missing, as all properties.
        Model().foodweb.mask,
        Property(
            trophic.mask, # (alias)
            "Component $(EN._Foodweb) is required to read this property.",
        ),
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
    @test v[2:end, end-1:end] == [0 0; 1 0]

    # Wrong access.
    @viewfails(v[], View, "Two indices are required to index into webs. Received 0: [].")
    for single in (nothing, 2, :b)
        @viewfails(
            v[single],
            View,
            "Two indices are required to index into webs. Received 1: [$(repr(single))]."
        )
    end
    @viewfails(
        v[0, 1],
        View,
        "Cannot index with [0, ·] into a :trophic web with 3 species source nodes."
    )
    @viewfails(
        v[:x, :b],
        View,
        "Cannot index with [:x, ·] into this :trophic web \
         because :x is not a node label in source class :species."
    )
    @viewfails(
        v[:a, :y],
        View,
        "Cannot index with [·, :y] into this :trophic web \
         because :y is not a node label in target class :species."
    )
    for index in (() -> v[nothing, 1], () -> v[1, nothing])
        @viewfails(
            index(),
            View,
            "Views are indexed with indices (::Int) or labels (::Symbol). \
             Cannot index with: $nothing ::$Nothing."
        )
    end

    # Immutable.
    mess = "Cannot mutate edges topology."
    @viewfails((v[1, 1] = true), View, mess)
    @viewfails((v[:a, :b] = false), View, mess)
    @viewfails((v[1:2, 2:end] = false), View, mess)
    # This takes priority over indexing semantics.
    @viewfails((v[] = true), View, mess)
    @viewfails((v[1, 2, 3] = true), View, mess)
    @viewfails((v[nothing] = true), View, mess)
    @viewfails((v[nothing, 1] = true), View, mess)
    @viewfails((v[1, nothing] = true), View, mess)

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
    @sysfails(
        Model(Foodweb([1 0 1; 0 1 0])),
        Check(
            early,
            [Foodweb.Matrix],
            "The adjacency matrix of size (3, 2) is not squared.\n\
             Received: 2×3 SparseMatrixCSC{Bool, $Int} with 3 stored entries:\n \
              1  ⋅  1\n \
              ⋅  1  ⋅",
        )
    )
    @sysfails(
        Model(Species(3), Foodweb([0 1; 0 0])),
        Check(
            late,
            [Foodweb.Matrix],
            "There are 3 :species nodes but the provided matrix is of size (2, 2).\n\
             Received: 2×2 SparseMatrixCSC{Bool, $Int} with 1 stored entry:\n \
              ⋅  1\n \
              ⋅  ⋅",
        )
    )

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
    @inputfails(
        Foodweb.Adjacency([:a => :b => :c]),
        "The pair at [1][right] \
         is just considered an iterable in this context, which may be confusing. \
         Consider grouping with an explicit vector instead like [:b, :c]."
    )
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
    @inputfails(
        Foodweb.Adjacency([1 => (2, 2)]),
        "Duplicated target node reference at [1][right][2]: 2 ::$Int."
    )
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
    @inputfails(
        Foodweb([1 => 2 0 1]),
        "Cannot convert input to either:\n  \
           - $(SparseMatrix{Bool})\n  \
           - $(EN.BinAdjacency)",
        [1 => 2 0 1],
    )

end

end

"""
Test all aspects of typical EdgeWeb component,
using Foodweb as an example, but without testing anything specific to the foodweb.
Anything specific to foodweb will be tested in a dedicated file.
"""
module EdgeWebTest

# What the end user should have to import.
using EcologicalNetworksDynamics
using SparseArrays

# Additional imports only used here for testing purpose.
using Test
import EcologicalNetworksDynamics: EN, Network, Views, EdgeWeb
import Main: is_repr, is_disp, @viewfails, @sysfails, @inputfails
const Value = Network # To have @sysfails work.
const V = Views.EdgesMaskView{EdgeWeb(:foodweb)} # Tested view type.

@testset "Typical EdgeWeb component" begin

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
    @test is_repr(
        bp,
        "<Foodweb>:Matrix(\
         A: 3×3 sparse matrix with 5 values (true), \
         species: <Species>)",
    )
    @test is_disp(
        bp,
        """
        blueprint for <Foodweb>: Matrix {
          A: 3×3 sparse matrix with 5 values (true),
          species: <implied blueprint for <Species>>,
        }\
        """,
    )

    # Explicit species names.
    bp.species = collect("abc")

    # Expand into a web component.
    m = Model(bp)

    # The names property becomes available as a view.
    v = m.foodweb.mask
    @test v isa V
    @test v isa AbstractMatrix{Bool}
    @test is_repr(v, "<foodweb>(3×3: 5 edges)")
    @test is_disp(
        v,
        """
        EdgesMaskView<foodweb>{Bool} (3×3: 5 edges)
         · 1 1
         1 · ·
         1 1 ·\
        """,
    )

    # The view has some basic vector-like interface.
    @test v == collect(v) == A == [i for i in v]

    # Index with either integers or labels.
    @test v[1, 1] == false
    @test v[1, 2] == true
    @test v[:a, :a] == false
    @test v[:a, :b] == true
    @test v[1:2, 2:3] == [1 1; 0 0]
    @test v[2:end, end-1:end] == [0 0; 1 0]

    # Wrong access.
    @viewfails(v[], V, "Two indices are required to index into webs. Received 0: [].")
    @viewfails(v[2], V, "Two indices are required to index into webs. Received 1: [2].")
    @viewfails(
        v[0, 1],
        V,
        "Cannot index with [0, ·] into a web :foodweb with 3 species source nodes."
    )
    @viewfails(
        v[:x, :b],
        V,
        "Cannot index with [:x, ·] into a web :foodweb \
         because :x is not a node label in source class :species."
    )
    @viewfails(
        v[:a, :y],
        V,
        "Cannot index with [·, :y] into a web :foodweb \
         because :y is not a node label in target class :species."
    )
    for index in (() -> v[nothing], () -> v[nothing, 1], () -> v[1, nothing])
        @viewfails(
            index(),
            V,
            "Views are indexed with indices (::Int) or labels (::Symbol). \
             Cannot index with: $nothing ::$Nothing."
        )
    end

    # Immutable.
    mess = "Cannot mutate edges topology."
    @viewfails((v[1, 1] = true), V, mess)
    @viewfails((v[:a, :b] = false), V, mess)
    @viewfails((v[1:2, 2:end] = false), V, mess)

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
        Model(Foodweb([1 1 1; 0 0 0])),
        Check(
            early,
            [Foodweb.Matrix],
            "The adjacency matrix of size (3, 2) is not squared.",
        )
    )
    @sysfails(
        Model(Foodweb([0 1; 0 0]; species = 3)),
        Check(
            late,
            [Foodweb.Matrix],
            "There are 3 :species nodes but the provided matrix is of size (2, 2).",
        )
    )

    # Various implicit/explicit forms for brought field in constructors.
    bp = Foodweb.Matrix(A, Species(2))
    @test bp == Foodweb.Matrix(A; species = Species(2))
    @test bp == Foodweb.Matrix(A, Species(2))
    @test bp == Foodweb.Matrix(A; species = 2)
    @test bp == Foodweb.Matrix(A, 2)
    @test bp == Foodweb(A; species = Species(2))
    @test bp == Foodweb(A; species = 2)
    @test bp == Foodweb(A, Species(2))
    @test bp == Foodweb(A, 2)

    # Construct from adjacency matrix.
    A = [:a => (:b, :c), (:d, :c) => (:b, :e)]
    bp = Foodweb.Adjacency(A)
    @test bp == Foodweb(A) # Directly dispatched from component.
    @test is_repr(
        bp,
        "<Foodweb>:Adjacency(A: {a: {b, c}, d: {b, e}, c: {b, e}}, species: <Species>)",
    )
    @test is_disp(
        bp,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {a: {b, c}, d: {b, e}, c: {b, e}},
          species: <implied blueprint for <Species>>,
        }\
        """,
    )
    # All list parsing errors are available here.
    @inputfails(
        Foodweb([:a => :b => :c]),
        "The pair at [1][right] \
         is just considered an iterable in this context, which may be confusing. \
         Consider grouping with an explicit vector instead like [:b, :c]."
    )

    m = Model(bp)
    @test m.trophic.mask ==
          m.trophic.matrix ==
          [
              0 1 1 0 0
              0 0 0 0 0
              0 1 0 0 1
              0 1 0 0 1
              0 0 0 0 0
          ]

    # The component enables other properties.
    @test m.trophic.n_edges == m.trophic.n_links == 6

end


end

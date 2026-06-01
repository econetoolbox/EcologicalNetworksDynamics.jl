"""
Test all aspects of typical EdgeField component,
using Efficiency as an example but without testing anything specific to efficiency.
Anything specific to efficiency will be tested in a dedicated file.
"""
module EdgeFieldTest

# What the end user should have to import.
using EcologicalNetworksDynamics
using SparseArrays

# Additional imports only used here for testing purpose.
using Test
using EcologicalNetworksDynamics: EN, N, SparseMatrix, Adjacency
import Main: is_repr, is_disp, @inputfails

@testset "Typical EdgeWeb component" begin

    @test Efficiency isa EN.Component
    @test is_repr(Efficiency, "Efficiency")
    @test is_disp(
        Efficiency,
        """
        Efficiency (component for $(N.Network), expandable from:
          Raw: raw values,
          Matrix: a sparse matrix,
          Adjacency: [species => [species => efficiency]] adjacency list,
          Flat: uniform value,
        )\
        """,
    )
    @test Efficiency.Raw <: EN.Blueprint
    @test Efficiency.Adjacency <: EN.Blueprint
    @test Efficiency.Flat <: EN.Blueprint

    base = Model(Foodweb([:a => :b, :b => :c, :d => (:a, :c)]))

    # Construct from raw values, regardless of input type.
    bp = Efficiency.Raw([2, 5, 8, 4] / 10)
    @test Efficiency.Raw(Bool[1, 0, 1, 0]) == Efficiency.Raw([1.0, 0.0, 1.0, 0.0])
    @test bp == Efficiency([2, 5, 8, 4] / 10) # Implicit constructor.
    @test Efficiency(Bool[1, 0, 1, 0]) == Efficiency([1.0, 0.0, 1.0, 0.0])
    @test is_repr(bp, "<Efficiency>:Raw(e: [0.2, 0.5, 0.8, 0.4])")
    @test is_disp(
        bp,
        """
        blueprint for <Efficiency>: Raw {
          e: [0.2, 0.5, 0.8, 0.4],
        }\
        """,
    )

    @inputfails(
        Efficiency('x'),
        "Cannot convert input to either:\n  \
          - $Float64\n  \
          - $Vector{$Float64}\n  \
          - $(SparseMatrix{Float64})\n  \
          - $(Adjacency{Float64})",
        'x',
    )
    @inputfails(
        Efficiency([0.1, 1.5, 0.3]),
        "When constructing <trophic:efficiency> from raw values:\n\
         At raw edge value [2]:\n\
         Value must belong to [0, 1].",
        1.5
    )

    # Construct from a matrix (here sparse).
    # TODO: test for dense constructs when such a component shows up.
    e = sparse([
        0 1 0 0
        0 0 2 0
        0 0 0 0
        3 0 4 0
    ] / 10)
    bp = Efficiency.Matrix(e)
    @test Efficiency.Matrix(Bool[0 1; 1 0]) == Efficiency.Matrix([0.0 1.0; 1.0 0.0])
    @test bp == Efficiency.Matrix(Matrix(e)) # From a dense matrix as well.
    @test bp == Efficiency(e) # Implicit constructor.
    @test is_repr(bp, "<Efficiency>:Matrix(e: 4×4:4 [0.1:0.4])")
    @test is_disp(
        bp,
        """
        blueprint for <Efficiency>: Matrix {
          e: 4×4 sparse matrix with 4 values (0.1 to 0.4),
        }\
        """,
    )

    @inputfails(
        Efficiency([0.1 0.5; -1 0.2]),
        "When constructing <trophic:efficiency> from a matrix:\n\
         On edge [2, 1]:\n\
         Value must belong to [0, 1].",
        -1.0
    )

    # Construct from adjacency lists.
    e = [:a => (:b => 0.1), :b => (:c => 0.2), :d => (:a => 0.3, :c => 0.4)]
    bp = Efficiency.Adjacency(e)

end

end

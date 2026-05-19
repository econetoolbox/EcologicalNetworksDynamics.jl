"""
Test all aspects of typical EdgeField component,
using Efficiency as an example but without testing anything specific to efficiency.
Anything specific to efficiency will be tested in a dedicated file.
"""
module EdgeFieldTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
using EcologicalNetworksDynamics: EN, N
import Main: is_repr, is_disp

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

end

end

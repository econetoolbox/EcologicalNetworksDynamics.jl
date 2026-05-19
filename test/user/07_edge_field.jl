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
using EcologicalNetworksDynamics: EN

@testset "Typical EdgeWeb component" begin

    @test Efficiency isa EN.Component
    @test is_repr(Efficiency, "Efficiency")
    @test is_disp(
        Efficiency,
        """
        Efficiency (component for $(N.Network), expandable from:
          Raw: raw values,
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
    e = [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10
    bp = Efficiency.Raw(e)

end

end

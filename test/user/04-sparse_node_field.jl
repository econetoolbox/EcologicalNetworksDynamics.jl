"""
Test all aspects of typical SparseNodeField component,
using producer Growth as an example but without testing anything specific to Growth.
Anything specific to Growth will be tested in a dedicated file.
"""
module SparseNodeFieldTest

using EcologicalNetworksDynamics
using SparseArrays

using Test
import EcologicalNetworksDynamics: EN, N, F, Network, Views, SparseNodeField
import Main: is_disp, is_repr, @sysfails, Value
const View = # Tested viewtype.
    Views.SparseNodesDataView{SparseNodeField(:producers, :growth, :species),Float64}

@testset "Typical SparseNodeField component" begin

    @test GrowthRate isa EN.Component
    @test is_repr(GrowthRate, "GrowthRate")
    @test is_disp(
        GrowthRate,
        """
        GrowthRate (component for $Network, expandable from:
          Raw: raw values,
          Map: [producers => growth] map,
          Flat: uniform value,
        )\
        """,
    )
    @test GrowthRate.Raw <: EN.Blueprint
    @test GrowthRate.Map <: EN.Blueprint
    @test GrowthRate.Flat <: EN.Blueprint

    # Growth rate is only defined / can only be set for producers.
    base = Model(Foodweb([:a => :b, :c => (:b, :d)]))
    @test base.producers.mask == [0, 1, 0, 1]

    # Careful: 'Raw' means 1 value per node in the subclass, not the parent.
    bp = GrowthRate.Raw([5, 8])
    @test bp == GrowthRate([5, 8])

    # Expand.
    m = base + bp
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 3 links, 2 producers, 2 consumers, 2 preys, 2 tops.
          - GrowthRate: [·, 5.0, ·, 8.0]\
        """,
    )
    @sysfails(Model(bp), Missing(Foodweb, GrowthRate, [GrowthRate.Raw], nothing))

    # The values become available as a view.
    v = m.growth_rate
    @test v isa View
    @test v isa AbstractVector{Float64}
    @test v isa AbstractSparseVector{Float64,Int}
    @test is_repr(v, "<species:producers:growth>[·, 5.0, ·, 8.0]")
    @test is_disp(
        v,
        """
        SparseNodesDataView<species:producers:growth>{Float64} (2/4 values)
         ·
         5.0
         ·
         8.0\
        """,
    )
    @sysfails( # Unless the component is missing, as all properties.
        Model().growth_rate,
        Property(
            growth_rate,
            "Component $(EN._GrowthRate) is required to read this property.",
        ),
    )

    # The view has some basic sparsee-vector-like interface.
    @test v == collect(v) == [0, 5, 0, 8] == [r for r in v] # HERE: fix.

end

end

module FoodwebTest

using EcologicalNetworksDynamics
using SparseArrays
using Random

using Test
using .EcologicalNetworksDynamics: F, V, D, EN
using Main: @viewfails, is_disp

@testset "Foodweb component." begin
    # Very structuring, the foodweb does provide a lot of properties.

    A = Bool[
        0 0 0 0
        1 0 0 0
        0 0 0 0
        1 1 1 0
    ]
    bp = Foodweb.Matrix(A)
    m = Model(Species("abcd"), bp)

    # Expanding the foodweb actually produces extra subclasses.
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(EN.Network)}) with 2 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 4 links, 2 producers, 2 consumers, 3 preys, 1 top.\
        """,
    )

    # Aliases.
    @test m.trophic === m.foodweb
    @test m.trophic.matrix === m.trophic.A
    @test m.trophic.matrix === m.foodweb.A
    @test m.trophic.matrix === m.A

    # Subclasses brought by the web.
    @test m.tops.mask == [0, 0, 0, 1]
    @test m.producers.mask == [1, 0, 1, 0]
    @test m.preys.mask == [1, 1, 1, 0]
    @test m.consumers.mask == [0, 1, 0, 1]

    # Webs brought by the web.
    @test m.producers_web.matrix == [
        1 0 1 0
        0 0 0 0
        1 0 1 0
        0 0 0 0
    ]
    @test m.herbivory.matrix == [
        0 0 0 0
        1 0 0 0
        0 0 0 0
        1 0 1 0
    ]
    @test m.carnivory.matrix == [
        0 0 0 0
        0 0 0 0
        0 0 0 0
        0 1 0 0
    ]

    # Aliases.
    @test m.producers.matrix == m.producers_web.matrix
    @test m.trophic.herbivory == m.herbivory
    @test m.trophic.carnivory == m.carnivory

    # Calculated trophic levels.
    @test m.trophic.level ≈ [1, 2, 1, 2 + 1 / 3]
    @viewfails(
        m.trophic.level[:d] = 1,
        V.NodesDataView{D.NodeField(:species, :trophic_level),Float64},
        "Values of :trophic_level are readonly."
    )

    # Construct from random models.
    # (further interface checking tested elsewhere as part of typical kwargs helpers use)
    Random.seed!(12)
    fw = Foodweb(:niche; S = 5, L = 5)
    @test fw.A == sparse([
        0 0 0 1 1
        1 1 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ])
    fw = Foodweb(:cascade; S = 5, C = 0.2)
    @test fw.A == sparse([
        0 0 0 0 1
        0 0 0 1 1
        0 0 0 1 0
        0 0 0 0 1
        0 0 0 0 0
    ])

end

end

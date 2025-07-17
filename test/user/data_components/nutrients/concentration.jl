module TestConcentration
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Nutrients concentration component." begin

    # Mostly duplicated from Efficiency.

    fw = Foodweb([:a => [:b, :c]])
    base = Model(fw, Nutrients.Nodes(3))

    cn = Nutrients.Concentration([
        1 2 3
        4 5 6
    ])
    m = base + cn
    @test m.nutrients.concentration == [
        1 2 3
        4 5 6
    ]
    @test typeof(cn) === Nutrients.Concentration.Raw

    # Adjacency list.
    cn = Nutrients.Concentration([
        :b => [:n1 => 1, :n2 => 2, :n3 => 3],
        :c => [:n2 => 5, :n3 => 6, :n1 => 4],
    ])
    m = base + cn
    @test m.nutrients.concentration == [
        1 2 3
        4 5 6
    ]
    @test typeof(cn) === Nutrients.Concentration.Adjacency

    # Scalar.
    cn = Nutrients.Concentration(2)
    m = base + cn
    @test m.nutrients.concentration == [
        2 2 2
        2 2 2
    ]
    @test typeof(cn) === Nutrients.Concentration.Flat

    #---------------------------------------------------------------------------------------
    # Imply Nutrients.

    c = [
        1 2 3
        4 5 6
    ]
    m = Model(fw, Nutrients.Concentration(c))
    @test has_component(m, Nutrients.Nodes)
    @test m.nutrients.concentration == c
    @test m.nutrients.names == [:n1, :n2, :n3]
    ms = Model(
        fw,
        Nutrients.Concentration([
            :b => [:x => 1, :y => 2, :z => 3],
            :c => [:z => 5, :x => 6, :y => 4],
        ]),
    )
    mi = Model(
        fw,
        Nutrients.Concentration([
            1 => [1 => 1, 2 => 2, 3 => 3],
            2 => [3 => 5, 1 => 6, 2 => 4],
        ]),
    )
    @test ms.nutrients.names == [:x, :y, :z]
    @test mi.nutrients.names == [:n1, :n2, :n3]
    @test ms.nutrients.concentration == mi.nutrients.concentration

    # ======================================================================================
    # Input guards.

    # Invalid values.
    @sysfails(
        base + Nutrients.Concentration([
            0 1 -2
            3 0 4
        ]),
        Check(
            early,
            [Nutrients.Concentration.Raw],
            "Not a positive value: c[1, 3] = -2.0.",
        )
    )

    @sysfails(
        base + Nutrients.Concentration([
            :b => [:n1 => 1, :n2 => 2, :n3 => 3],
            :c => [:n2 => 5, :n3 => -6, :n1 => 4],
        ]),
        Check(
            early,
            [Nutrients.Concentration.Adjacency],
            "Not a positive value: c[:c, :n3] = -6.0.",
        )
    )

    @sysfails(
        base + Nutrients.Concentration(-5),
        Check(early, [Nutrients.Concentration.Flat], "Not a positive value: c = -5.0.")
    )

    # Invalid size.
    @sysfails(
        base + Nutrients.Concentration([
            0 1
            3 0
        ]),
        Check(
            late,
            [Nutrients.Concentration.Raw],
            "Invalid size for parameter 'c': expected (2, 3), got (2, 2).",
        )
    )

    # Non-dense input.
    @sysfails(
        Model(
            fw,
            Nutrients.Concentration([
                :b => [:x => 1, :y => 2],
                :c => [:z => 5, :x => 6, :y => 4],
            ]),
        ),
        Check(
            late,
            [Nutrients.Concentration.Adjacency],
            "Missing 'producer trophic' edge label in 'c': \
             no value specified for [:b, :z].",
        )
    )

    # Respect template.
    @sysfails(
        Model(
            fw,
            Nutrients.Concentration([
                :b => [:x => 1, :y => 2, :z => 3],
                :a => [:z => 5, :x => 6, :y => 4],
            ]),
        ),
        Check(
            late,
            [Nutrients.Concentration.Adjacency],
            "Invalid 'producer trophic' edge label in 'c'. \
             Expected either :b or :c, got instead: [:a] (5.0).",
        )
    )

end

end

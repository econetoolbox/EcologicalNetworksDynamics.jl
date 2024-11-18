@testset "Nutrients half-saturation component." begin

    # Mostly duplicated from Concentration.

    fw = Foodweb([:a => [:b, :c]])
    base = Model(fw, Nutrients.Nodes(3))

    cn = Nutrients.HalfSaturation([
        1 2 3
        4 5 6
    ])
    m = base + cn
    @test m.nutrients.half_saturation == [
        1 2 3
        4 5 6
    ]
    @test typeof(cn) === Nutrients.HalfSaturation.Raw

    # Adjacency list.
    cn = Nutrients.HalfSaturation([
        :b => [:n1 => 1, :n2 => 2, :n3 => 3],
        :c => [:n2 => 5, :n3 => 6, :n1 => 4],
    ])
    m = base + cn
    @test m.nutrients.half_saturation == [
        1 2 3
        4 5 6
    ]
    @test typeof(cn) === Nutrients.HalfSaturation.Adjacency

    # Scalar.
    cn = Nutrients.HalfSaturation(2)
    m = base + cn
    @test m.nutrients.half_saturation == [
        2 2 2
        2 2 2
    ]
    @test typeof(cn) === Nutrients.HalfSaturation.Flat

    #---------------------------------------------------------------------------------------
    # Imply Nutrients.

    h = [
        1 2 3
        4 5 6
    ]
    m = Model(fw, Nutrients.HalfSaturation(h))
    @test has_component(m, Nutrients.Nodes)
    @test m.nutrients.half_saturation == h
    @test m.nutrients.names == [:n1, :n2, :n3]
    ms = Model(
        fw,
        Nutrients.HalfSaturation([
            :b => [:x => 1, :y => 2, :z => 3],
            :c => [:z => 5, :x => 6, :y => 4],
        ]),
    )
    mi = Model(
        fw,
        Nutrients.HalfSaturation([
            # Careful: this is *producer* dense index.
            1 => [1 => 1, 2 => 2, 3 => 3],
            2 => [3 => 5, 1 => 6, 2 => 4],
        ]),
    )
    @test ms.nutrients.names == [:x, :y, :z]
    @test mi.nutrients.names == [:n1, :n2, :n3]
    @test ms.nutrients.half_saturation == mi.nutrients.half_saturation

    # ======================================================================================
    # Input guards.

    # Invalid values.
    @sysfails(
        base + Nutrients.HalfSaturation([
            0 1 -2
            3 0 4
        ]),
        Check(
            early,
            [Nutrients.HalfSaturation.Raw],
            "Not a positive value: h[1, 3] = -2.0.",
        )
    )

    @sysfails(
        base + Nutrients.HalfSaturation([
            :b => [:n1 => 1, :n2 => 2, :n3 => 3],
            :c => [:n2 => 5, :n3 => -6, :n1 => 4],
        ]),
        Check(
            early,
            [Nutrients.HalfSaturation.Adjacency],
            "Not a positive value: h[:c, :n3] = -6.0.",
        )
    )

    @sysfails(
        base + Nutrients.HalfSaturation(-5),
        Check(early, [Nutrients.HalfSaturation.Flat], "Not a positive value: h = -5.0.")
    )

    # Invalid size.
    @sysfails(
        base + Nutrients.HalfSaturation([
            0 1
            3 0
        ]),
        Check(
            late,
            [Nutrients.HalfSaturation.Raw],
            "Invalid size for parameter 'h': expected (2, 3), got (2, 2).",
        )
    )

    # Non-dense input.
    @sysfails(
        Model(
            fw,
            Nutrients.HalfSaturation([
                :b => [:x => 1, :y => 2],
                :c => [:z => 5, :x => 6, :y => 4],
            ]),
        ),
        Check(
            late,
            [Nutrients.HalfSaturation.Adjacency],
            "Missing 'producer trophic' edge label in 'h': \
             no value specified for [:b, :z].",
        )
    )

    # Respect template.
    @sysfails(
        Model(
            fw,
            Nutrients.HalfSaturation([
                :b => [:x => 1, :y => 2, :z => 3],
                :a => [:z => 5, :x => 6, :y => 4],
            ]),
        ),
        Check(
            late,
            [Nutrients.HalfSaturation.Adjacency],
            "Invalid 'producer trophic' edge label in 'h'. \
             Expected either :b or :c, got instead: [:a] (5.0).",
        )
    )

end

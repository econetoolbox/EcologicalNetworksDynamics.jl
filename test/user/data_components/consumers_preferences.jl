@testset "Consumers preferences component." begin

    # Mostly duplicated from ConsumersPreferences.

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # Construct from raw values.

    # Matrix.
    cp = ConsumersPreferences([
        0 1 2
        0 0 3
        0 0 0
    ])
    m = base + cp
    @test m.consumers.preferences == m.w == [
        0 1 2
        0 0 3
        0 0 0
    ]
    @test typeof(cp) === ConsumersPreferences.Raw

    # Adjacency list.
    for adj in (
        #! format: off
        [:a => [:b => 1], :b => [:c => 3]],
        [1 => [2 => 1], 2 => [3 => 3]],
        #! format: on
    )
        cp = ConsumersPreferences(adj)
        m = base + cp
        @test m.consumers.preferences == m.w == [
            0 1 0
            0 0 3
            0 0 0
        ]
        @test typeof(cp) == ConsumersPreferences.Adjacency
    end

    # Scalar.
    cp = ConsumersPreferences(1)
    m = base + cp
    @test m.consumers.preferences == m.w == [
        0 1 1
        0 0 1
        0 0 0
    ]
    @test typeof(cp) == ConsumersPreferences.Flat

    #---------------------------------------------------------------------------------------
    # Construct from the foodweb.

    cp = ConsumersPreferences()
    m = base + cp
    @test m.consumers.preferences == m.w == [
        0 1 1
        0 0 2
        0 0 0
    ] / 2
    @test typeof(cp) == ConsumersPreferences.Homogeneous

    #---------------------------------------------------------------------------------------
    # Imply foodweb.

    w = [
        1 2 0
        0 0 3
        0 0 0
    ]
    m = Model(ConsumersPreferences(w))
    @test has_component(m, Foodweb)
    @test m.species.names == [:s1, :s2, :s3]
    @test m.A == [
        1 1 0
        0 0 1
        0 0 0
    ]
    @test Model(Species([:a, :b, :c]), ConsumersPreferences(w)).species.names ==
          [:a, :b, :c]
    # Imply species names via foodweb implication.
    @test Model(
        ConsumersPreferences([:a => [:a => 0.1, :b => 0.2], :b => [:c => 0.3]]),
    ).species.names == [:a, :b, :c]
    @test Model(
        ConsumersPreferences([2 => [3 => 0.3], 1 => [1 => 0.1, 2 => 0.2]]),
    ).species.names == [:s1, :s2, :s3]

    # ======================================================================================
    # Input guards.

    # Invalid values.
    @sysfails(
        base + ConsumersPreferences([
            0 1 -2
            3 0 4
            0 0 0
        ]),
        Check(early, [ConsumersPreferences.Raw], "Not a positive value: w[1, 3] = -2.0.")
    )

    @sysfails(
        base + ConsumersPreferences([:b => [:c => -5]]),
        Check(
            early,
            [ConsumersPreferences.Adjacency],
            "Not a positive value: w[:b, :c] = -5.0.",
        )
    )

    @sysfails(
        base + ConsumersPreferences(-5),
        Check(early, [ConsumersPreferences.Flat], "Not a positive value: w = -5.0.")
    )

    # Respect template.
    @sysfails(
        base + ConsumersPreferences([
            0 1 2
            3 0 4
            0 0 0
        ]),
        Check(
            late,
            [ConsumersPreferences.Raw],
            "Non-missing value found for 'w' at edge index [2, 1] (3.0), \
             but the template for 'trophic links' only allows values \
             at the following indices:\n  [(1, 2), (1, 3), (2, 3)]",
        )
    )

    @sysfails(
        base + ConsumersPreferences([:b => [:a => 5]]),
        Check(
            late,
            [ConsumersPreferences.Adjacency],
            "Invalid 'trophic link' edge label in 'w': [:b, :a] (5.0). \
             Valid edges target labels for source [:b] in this template are:\n  [:c]",
        )
    )

end

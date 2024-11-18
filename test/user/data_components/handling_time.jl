@testset "'Handling time' component." begin

    # Mostly duplicated from Efficiency.

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # Construct from raw values.

    # Matrix.
    ht = HandlingTime([
        0 1 2
        0 0 3
        0 0 0
    ])
    m = base + ht
    @test m.handling_time == [
        0 1 2
        0 0 3
        0 0 0
    ]
    @test typeof(ht) === HandlingTime.Raw

    # Adjacency list.
    for adj in (
        #! format: off
        [:a => [:b => 1], :b => [:c => 3]],
        [1 => [2 => 1], 2 => [3 => 3]],
        #! format: on
    )
        ht = HandlingTime(adj)
        m = base + ht
        @test m.handling_time == [
            0 1 0
            0 0 3
            0 0 0
        ]
        @test typeof(ht) == HandlingTime.Adjacency
    end

    # Scalar.
    ht = HandlingTime(2)
    m = base + ht
    @test m.handling_time == [
        0 2 2
        0 0 2
        0 0 0
    ]
    @test typeof(ht) == HandlingTime.Flat

    #---------------------------------------------------------------------------------------
    # Construct from body masses.

    ht = HandlingTime(:Miele2019)
    @sysfails(base + ht, Missing(BodyMass, nothing, [HandlingTime.Miele2019], nothing))
    base += BodyMass(; Z = 1)
    m = base + ht
    @test m.handling_time == [
        0 3 3
        0 0 3
        0 0 0
    ] / 10
    @test typeof(ht) == HandlingTime.Miele2019

    #---------------------------------------------------------------------------------------
    # From temperature.

    ht = HandlingTime(:Binzer2016)
    @test ht.E_a == 0.26
    @test ht.allometry[:i][:a] == exp(9.66)
    @test ht.allometry[:e][:c] == 0.47
    @test typeof(ht) == HandlingTime.Temperature

    @sysfails(base + ht, Missing(Temperature, nothing, [HandlingTime.Temperature], nothing))
    base += Temperature(298.5)
    @sysfails(
        base + ht,
        Missing(MetabolicClass, nothing, [HandlingTime.Temperature], nothing)
    )
    base += MetabolicClass(:all_invertebrates)
    m = base + ht
    h = 13036.720443481181
    @test m.handling_time == [
        0 h h
        0 0 h
        0 0 0
    ]

    #---------------------------------------------------------------------------------------
    # Imply foodweb.

    h_t = [
        1 2 0
        0 0 3
        0 0 0
    ]
    m = Model(HandlingTime(h_t))
    @test has_component(m, Foodweb)
    @test m.species.names == [:s1, :s2, :s3]
    @test m.A == [
        1 1 0
        0 0 1
        0 0 0
    ]
    @test Model(Species([:a, :b, :c]), HandlingTime(h_t)).species.names == [:a, :b, :c]
    # Imply species names via foodweb implication.
    @test Model(HandlingTime([:a => [:a => 1, :b => 2], :b => [:c => 3]])).species.names ==
          [:a, :b, :c]
    @test Model(HandlingTime([2 => [3 => 0.3], 1 => [1 => 0.1, 2 => 0.2]])).species.names ==
          [:s1, :s2, :s3]

    # ======================================================================================
    # Input guards.

    # Invalid values.
    @sysfails(
        base + HandlingTime([
            0 1 -2
            3 0 4
            0 0 0
        ]),
        Check(early, [HandlingTime.Raw], "Not a positive value: h_t[1, 3] = -2.0.")
    )

    @sysfails(
        base + HandlingTime([:b => [:c => -5]]),
        Check(early, [HandlingTime.Adjacency], "Not a positive value: h_t[:b, :c] = -5.0.")
    )

    @sysfails(
        base + HandlingTime(-5),
        Check(early, [HandlingTime.Flat], "Not a positive value: h_t = -5.0.")
    )

    # Respect template.
    @sysfails(
        base + HandlingTime([
            0 1 2
            3 0 4
            0 0 0
        ]),
        Check(
            late,
            [HandlingTime.Raw],
            "Non-missing value found for 'h_t' at edge index [2, 1] (3.0), \
             but the template for 'trophic links' only allows values \
             at the following indices:\n  [(1, 2), (1, 3), (2, 3)]",
        )
    )

    @sysfails(
        base + HandlingTime([:b => [:a => 5]]),
        Check(
            late,
            [HandlingTime.Adjacency],
            "Invalid 'trophic link' edge label in 'h_t': [:b, :a] (5.0). \
             Valid edges target labels for source [:b] in this template are:\n  [:c]",
        )
    )

end

@testset "Efficiency component." begin

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # Construct from raw values.

    # Matrix.
    ef = Efficiency([
        0 1 2
        0 0 3
        0 0 0
    ] / 10)
    m = base + ef
    @test m.efficiency == m.e == [
        0 1 2
        0 0 3
        0 0 0
    ] / 10
    @test typeof(ef) === Efficiency.Raw

    # Adjacency list.
    for adj in
        #! format: off
        ([:a => [:b => 0.1], :b => [:c => 0.3]],
         [1 => [2 => 0.1], 2 => [3 => 0.3]])
        #! format: on
        ef = Efficiency(adj)
        m = base + ef
        @test m.efficiency == m.e == [
            0 1 0
            0 0 3
            0 0 0
        ] / 10
        @test typeof(ef) == Efficiency.Adjacency
    end

    # Scalar.
    ef = Efficiency(0.1)
    m = base + ef
    @test m.efficiency == m.e == [
        0 1 1
        0 0 1
        0 0 0
    ] / 10
    @test typeof(ef) == Efficiency.Flat

    #---------------------------------------------------------------------------------------
    # Construct from the foodweb.

    ef = Efficiency(:Miele2019; e_herbivorous = 0.2, e_carnivorous = 0.4)
    m = base + ef
    @test m.efficiency == m.e == [
        0 4 2
        0 0 2
        0 0 0
    ] / 10
    @test typeof(ef) == Efficiency.Miele2019

    #---------------------------------------------------------------------------------------
    # Imply foodweb.

    e = [
        1 2 0
        0 0 3
        0 0 0
    ] / 10
    m = Model(Efficiency(e))
    @test has_component(m, Foodweb)
    @test m.species.names == [:s1, :s2, :s3]
    @test m.A == [
        1 1 0
        0 0 1
        0 0 0
    ]
    @test Model(Species([:a, :b, :c]), Efficiency(e)).species.names == [:a, :b, :c]
    # Imply species names via foodweb implication.
    @test Model(
        Efficiency([:a => [:a => 0.1, :b => 0.2], :b => [:c => 0.3]]),
    ).species.names == [:a, :b, :c]
    @test Model(Efficiency([2 => [3 => 0.3], 1 => [1 => 0.1, 2 => 0.2]])).species.names ==
          [:s1, :s2, :s3]

    # ======================================================================================
    # Input guards.

    # Forbid unused arguments.
    @argfails(Efficiency(:Miele2019; e_other = 5), "Unexpected argument: e_other = 5.")

    @argfails(Efficiency(0.2; a = 5), "Unexpected argument: a = 5.")

    # Invalid values.
    @sysfails(
        base + Efficiency([
            0 1 2
            3 0 4
            0 0 0
        ]),
        Check(early, [Efficiency.Raw], "Not a value within [0, 1]: e[2, 1] = 3.0.")
    )

    @sysfails(
        base + Efficiency([:b => [:c => 5]]),
        Check(early, [Efficiency.Adjacency], "Not a value within [0, 1]: e[:b, :c] = 5.0.")
    )

    @sysfails(
        base + Efficiency(5),
        Check(early, [Efficiency.Flat], "Not a value within [0, 1]: e = 5.0.")
    )

    # Respect template.
    @sysfails(
        base + Efficiency([
            0 1 2
            3 0 4
            0 0 0
        ] / 10),
        Check(
            late,
            [Efficiency.Raw],
            "Non-missing value found for 'e' at edge index [2, 1] (0.3), \
             but the template for 'trophic links' only allows values \
             at the following indices:\n  [(1, 2), (1, 3), (2, 3)]",
        )
    )

    @sysfails(
        base + Efficiency([:b => [:a => 0.5]]),
        Check(
            late,
            [Efficiency.Adjacency],
            "Invalid 'trophic link' edge label in 'e': [:b, :a] (0.5). \
             Valid edges target labels for source [:b] in this template are:\n  [:c]",
        )
    )

end

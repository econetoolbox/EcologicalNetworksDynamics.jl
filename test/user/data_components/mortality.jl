@testset "Mortality component." begin

    # Mostly duplicated from Growth.

    base = Model()

    #---------------------------------------------------------------------------------------
    # From raw values.

    # From a dense vector.
    mr = Mortality([1, 2, 3])
    m = base + mr
    @test m.mortality == [1, 2, 3] == m.d
    @test m.species.names == [:s1, :s2, :s3] # Implied.
    @test typeof(mr) == Mortality.Raw

    # From a single value.
    mr = Mortality(2)
    m = base + Species(3) + mr
    @test m.mortality == [2, 2, 2] == m.d
    @test typeof(mr) == Mortality.Flat

    # Map selected species.
    ## Integer keys.
    mr = Mortality([2 => 3, 3 => 2, 1 => 1])
    m = base + mr
    @test m.mortality == [1, 3, 2] == m.d
    @test m.species.names == [:s1, :s2, :s3]
    @test typeof(mr) == Mortality.Map

    ## Symbol keys.
    mr = Mortality([:a => 1, :b => 2, :c => 3])
    m = base + mr
    @test m.mortality == [1, 2, 3] == m.d
    @test m.species.names == [:a, :b, :c]
    @test typeof(mr) == Mortality.Map

    # Imply species component.
    @test Model(Mortality([1, 2, 3])).species.names == [:s1, :s2, :s3]
    @test Model(Mortality([:a => 1, :b => 2, :c => 3])).species.names == [:a, :b, :c]

    #---------------------------------------------------------------------------------------
    # From allometric rates.

    base = Model(
        Foodweb([:a => [:b, :c], :b => :c]),
        BodyMass(1.5),
        MetabolicClass(:all_invertebrates),
    )

    mr = Mortality(:Miele2019)
    @test mr.allometry[:p][:a] == 0.0138
    @test mr.allometry[:p][:b] == -1 / 4
    m = base + mr
    @test m.mortality == [0.028373102913349126, 0.028373102913349126, 0.012469707649815859]
    @test typeof(mr) == Mortality.Allometric

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(Model(Mortality(1)), Missing(Species, Mortality, [Mortality.Flat], nothing))

    @sysfails(
        base + Mortality([1, 2]),
        Check(
            late,
            [Mortality.Raw],
            "Invalid size for parameter 'd': expected (3,), got (2,).",
        )
    )

    @sysfails(
        base + Mortality([:a => 1, :b => 2]),
        Check(
            late,
            [Mortality.Map],
            "Missing 'species' node label in 'd': no value specified for [:c].",
        )
    )

    @sysfails(
        base + Mortality([:a => 1, :b => 2, :c => 3, :d => 4]),
        Check(
            late,
            [Mortality.Map],
            "Invalid 'species' node label in 'd'. \
             Expected either :a, :b or :c, got instead: [:d] (4.0).",
        )
    )

    @sysfails(
        base + Mortality([0, -1, +1]),
        Check(early, [Mortality.Raw], "Not a positive value: d[2] = -1.0.")
    )

    @sysfails(
        base + Mortality(-1),
        Check(early, [Mortality.Flat], "Not a positive value: d = -1.0.")
    )

    @sysfails(
        base + Mortality([:a => 0, :b => -1, :c => 1]),
        Check(early, [Mortality.Map], "Not a positive value: d[:b] = -1.0.")
    )

    #---------------------------------------------------------------------------------------
    # Allometry.

    # Forbid unnecessary allometric parameters.
    @sysfails(
        base + Mortality.Allometric(; p = (a = 1, b = 0.25, c = 8)),
        Check(
            early,
            [Mortality.Allometric],
            "Allometric parameter 'c' (target_exponent) for 'producer' \
             is meaningless in the context of calculating mortality rates: 8.0.",
        )
    )

    @sysfails(
        base + Mortality.Allometric(; p = (a = 1, b = 0.25), i_a = 8),
        Check(
            early,
            [Mortality.Allometric],
            "Missing allometric parameter 'b' (source_exponent) for 'invertebrate', \
             required to calculate mortality rates.",
        )
    )

    # ======================================================================================
    # Edit guards.

    @failswith(
        (m.mortality[3] = -2),
        WriteError("Not a positive value: d[3] = -2.", :mortality, (3,), -2),
    )

end

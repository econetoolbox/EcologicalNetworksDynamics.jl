module TestMetabolism
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Metabolism component." begin

    # Mostly duplicated from Mortality.

    base = Model()

    #---------------------------------------------------------------------------------------
    # From raw values.

    # From a dense vector.
    mb = Metabolism([1, 2, 3])
    m = base + mb
    @test m.metabolism == [1, 2, 3] == m.x
    @test typeof(mb) == Metabolism.Raw

    # From a single value.
    mb = Metabolism(2)
    m = base + Species(3) + mb
    @test m.metabolism == [2, 2, 2] == m.x
    @test typeof(mb) == Metabolism.Flat

    # Map selected species.
    ## Integer keys.
    mb = Metabolism([2 => 3, 3 => 2, 1 => 1])
    m = base + mb
    @test m.metabolism == [1, 3, 2] == m.x
    @test m.species.names == [:s1, :s2, :s3]
    @test typeof(mb) == Metabolism.Map

    ## Symbol keys.
    mb = Metabolism([:a => 1, :b => 2, :c => 3])
    m = base + mb
    @test m.metabolism == [1, 2, 3] == m.x
    @test m.species.names == [:a, :b, :c]
    @test typeof(mb) == Metabolism.Map

    # Imply species component.
    @test Model(Metabolism([1, 2, 3])).species.names == [:s1, :s2, :s3]
    @test Model(Metabolism([:a => 1, :b => 2, :c => 3])).species.names == [:a, :b, :c]

    #---------------------------------------------------------------------------------------
    # From allometric rates.

    base = Model(
        Foodweb([:a => [:b, :c], :b => :c]),
        BodyMass(1.5),
        MetabolicClass(:all_invertebrates),
    )

    mb = Metabolism(:Miele2019)
    @test mb.allometry[:i][:a] == 0.314
    @test mb.allometry[:i][:b] == -1 / 4
    m = base + mb
    @test m.metabolism == [0.2837310291334913, 0.2837310291334913, 0.0]
    @test typeof(mb) == Metabolism.Allometric

    #---------------------------------------------------------------------------------------
    # From temperature.

    mb = Metabolism(:Binzer2016)
    @test mb.E_a == -0.69
    @test mb.allometry[:i][:a] == 6.557967639824989e-8
    @test mb.allometry[:invertebrate][:source_exponent] == -0.31 == mb.allometry[:i][:b]
    @test typeof(mb) == Metabolism.Temperature

    m = base + Temperature(298.5) + mb
    @test m.metabolism == [9.436206283089092e-8, 9.436206283089092e-8, 0.0]

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        Model(Metabolism(1)),
        Missing(Species, Metabolism, [Metabolism.Flat], nothing)
    )

    @sysfails(
        base + Metabolism([1, 2]),
        Check(
            late,
            [Metabolism.Raw],
            "Invalid size for parameter 'x': expected (3,), got (2,).",
        )
    )

    @sysfails(
        base + Metabolism([:a => 1, :b => 2]),
        Check(
            late,
            [Metabolism.Map],
            "Missing 'species' node label in 'x': no value specified for [:c].",
        )
    )

    @sysfails(
        base + Metabolism([:a => 1, :b => 2, :c => 3, :w => 4]),
        Check(
            late,
            [Metabolism.Map],
            "Invalid 'species' node label in 'x'. \
             Expected either :a, :b or :c, got instead: [:w] (4.0).",
        )
    )

    @sysfails(
        base + Metabolism([0, -1, +1]),
        Check(early, [Metabolism.Raw], "Not a positive value: x[2] = -1.0.")
    )

    @sysfails(
        base + Metabolism(-1),
        Check(early, [Metabolism.Flat], "Not a positive value: x = -1.0.")
    )

    @sysfails(
        base + Metabolism([:a => 0, :b => -1, :c => 1]),
        Check(early, [Metabolism.Map], "Not a positive value: x[:b] = -1.0.")
    )

    #---------------------------------------------------------------------------------------
    # Allometry.

    # Forbid unnecessary allometric parameters.
    @sysfails(
        base + Metabolism.Allometric(; p = (a = 1, b = 0.25, c = 8)),
        Check(
            early,
            [Metabolism.Allometric],
            "Allometric parameter 'c' (target_exponent) for 'producer' \
             is meaningless in the context of calculating metabolism rates: 8.0.",
        )
    )

    @sysfails(
        base + Metabolism.Allometric(; p = (a = 1, b = 0.25), i_a = 8),
        Check(
            early,
            [Metabolism.Allometric],
            "Missing allometric parameter 'b' (source_exponent) for 'invertebrate', \
             required to calculate metabolism rates.",
        )
    )

    # Forbid if no temperature is available.
    @sysfails(base + mb, Missing(Temperature, nothing, [Metabolism.Temperature], nothing))

    # ======================================================================================
    # Edit guards.

    @failswith(
        (m.metabolism[3] = -2),
        WriteError("Not a positive value: x[3] = -2.", :metabolism, (3,), -2),
    )

end

end

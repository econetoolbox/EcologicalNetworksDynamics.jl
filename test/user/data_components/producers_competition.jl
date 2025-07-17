module TestProducersCompetition
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "ProducersCompetition component." begin

    # Mostly duplicated from Efficiency.

    base = Model(Foodweb([:a => [:b, :c]]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Matrix.
    pc = ProducersCompetition([
        0 0 0
        0 1 3
        0 2 4
    ])
    m = base + pc
    @test m.producers.competition.matrix == [
        0 0 0
        0 1 3
        0 2 4
    ]
    @test m.producers.competition.mask == [
        0 0 0
        0 1 1
        0 1 1
    ]
    @test typeof(pc) === ProducersCompetition.Raw

    # Adjacency list.
    m = base + ProducersCompetition([:b => [:b => 1, :c => 3], :c => [:c => 4]])
    @test m.producers.competition.matrix == [
        0 0 0
        0 1 3
        0 0 4
    ]
    @test typeof(pc) == ProducersCompetition.Raw

    # Scalar.
    pc = ProducersCompetition(2)
    m = base + pc
    @test m.producers.competition.matrix == [
        0 0 0
        0 2 2
        0 2 2
    ]
    @test typeof(pc) == ProducersCompetition.Flat

    #---------------------------------------------------------------------------------------
    # Construct from diagonal matrix.

    pc = ProducersCompetition(; diag = 1, off = 2)
    m = base + pc
    @test m.producers.competition.matrix == [
        0 0 0
        0 1 2
        0 2 1
    ]
    # Fancy input aliases.
    @test pc == ProducersCompetition(; diagonal = 1, nondiagonal = 2)
    @test pc == ProducersCompetition(; diagonal = 1, offdiagonal = 2)
    @test pc == ProducersCompetition(; diag = 1, offdiag = 2)
    @test pc == ProducersCompetition(; diag = 1, rest = 2)
    @test pc == ProducersCompetition(; d = 1, o = 2)
    @test pc == ProducersCompetition(; d = 1, nd = 2)
    @test typeof(pc) == ProducersCompetition.Diagonal

    # ======================================================================================
    # Input guards.

    #---------------------------------------------------------------------------------------
    # Invalid arguments.

    @argfails(ProducersCompetition(), "No input provided to specify producers competition.")
    @argfails(
        ProducersCompetition(nothing),
        "No input provided to specify producers competition."
    )

    @argfails(ProducersCompetition(; d = 1, o = 2, x = 3), "Unexpected argument: x = 3.")

    @argfails(
        ProducersCompetition(0.2; a = 5),
        "No need to provide both alpha matrix and keyword arguments."
    )

    @argfails(
        ProducersCompetition(; diag = 1, off = 2, d = 3),
        "Cannot specify both aliases :d and :diag arguments."
    )

    #---------------------------------------------------------------------------------------
    # Invalid values.

    @sysfails(
        base + ProducersCompetition([
            0 0 0
            0 1 3
            0 -2 4
        ]),
        Check(
            early,
            [ProducersCompetition.Raw],
            "Not a positive value: alpha[3, 2] = -2.0.",
        )
    )

    @sysfails(
        base + ProducersCompetition([:b => [:c => -5]]),
        Check(
            early,
            [ProducersCompetition.Adjacency],
            "Not a positive value: alpha[:b, :c] = -5.0.",
        )
    )

    @sysfails(
        base + ProducersCompetition(-5),
        Check(early, [ProducersCompetition.Flat], "Not a positive value: alpha = -5.0.")
    )

    @sysfails(
        base + ProducersCompetition(; d = -5),
        Check(
            early,
            [ProducersCompetition.Diagonal],
            "Not a positive value: alpha[:diag] = -5.0.",
        )
    )

    @sysfails(
        base + ProducersCompetition(; d = 5, o = -3),
        Check(
            early,
            [ProducersCompetition.Diagonal],
            "Not a positive value: alpha[:off] = -3.0.",
        )
    )

    #---------------------------------------------------------------------------------------
    # Respect template.

    @sysfails(
        base + ProducersCompetition([
            0 0 0
            5 1 3
            0 2 4
        ]),
        Check(
            late,
            [ProducersCompetition.Raw],
            "Non-missing value found for 'alpha' at edge index [2, 1] (5.0), \
             but the template for 'producers links' only allows values \
             at the following indices:\n  [(2, 2), (3, 2), (2, 3), (3, 3)]",
        )
    )

    @sysfails(
        base + ProducersCompetition([:b => [:a => 5]]),
        Check(
            late,
            [ProducersCompetition.Adjacency],
            "Invalid 'producers link' edge label in 'alpha': [:b, :a] (5.0). \
             Valid edges target labels for source [:b] in this template are:\n  [:b, :c]",
        )
    )

end

end

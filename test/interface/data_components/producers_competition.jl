module ProducersCompetitionTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    SL, @test_repr, @test_disp, @argfails, @bpfails, addfails
using Test

const s, S = SL.EdgeField(:inter_producers, :competition)

@testset "ProducersCompetition" begin

    @test ProducersCompetition isa Component

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c]]))

    # One extra blueprint has it build from a diagonal matrix.
    @test ProducersCompetition.Diagonal <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = ProducersCompetition.Diagonal(; diag = 5, off = 8)
    @test bp.diag isa Float64
    @test bp.off isa Float64
    @test (bp.diag, bp.off) == (5, 8)
    @test bp == ProducersCompetition(; diag = 5, off = 8)
    @test bp == ProducersCompetition(; d = 5, o = 8) # ((quite) some aliases)
    @test bp == ProducersCompetition(; diagonal = 5, offdiagonal = 8)
    @test bp == ProducersCompetition(; d = 5, rest = 8)
    @test bp == ProducersCompetition(; d = 5, nondiagonal = 8)
    @test bp == ProducersCompetition(; d = 5, nd = 8)
    @test_repr(bp, "<ProducersCompetition>:Diagonal(diag: 5.0, off: 8.0)")
    @test_disp(bp,
        """
        blueprint for <ProducersCompetition>: Diagonal {
          diag: 5.0,
          off: 8.0,
        }\
        """)

    # Default values.
    bp = ProducersCompetition.Diagonal()
    @test bp == ProducersCompetition(; diag = 1, off = 0)
    @test bp == ProducersCompetition(; diag = 1)
    @test bp == ProducersCompetition(; off = 0)

    @argfails(ProducersCompetition.Diagonal(5), "Unexpected positional argument: 5  ::$Int")
    @argfails(ProducersCompetition.Diagonal(; x = 5), "Unexpected argument: x = 5.")

    #---------------------------------------------------------------------------------------
    # Early check.
    @bpfails(ProducersCompetition.Diagonal(; diag = -2),
        ProducersCompetition.Diagonal, :construct,
        (s, -2.0, :uwhole, "Value cannot be negative."))
    bp.off -= 5
    addfails.@check(base + bp, [],
        (ProducersCompetition.Diagonal, :early,
            (s, -5.0, :uwhole, "Value cannot be negative.")))
    # TODO: report field name instead. Introduce IT.fields_check(::Type{BP})?

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = ProducersCompetition.Diagonal(; diag = 7, off = 8)
    m = base + bp
    @test m.producers.competition == m.producers_competition == [
        7 8 8
        8 7 8
        8 8 7
    ]

    addfails.@missing(Model(bp),
        Foodweb, ProducersCompetition, [ProducersCompetition.Diagonal], nothing)

end

end

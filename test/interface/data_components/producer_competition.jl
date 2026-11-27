module ProducerCompetitionTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    SL, @test_repr, @test_disp, @argfails, @bpfails, addfails
using Test

const s, S = SL.EdgeField(:inter_producer, :competition)

@testset "ProducerCompetition." begin

    @test ProducerCompetition isa Component

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c]]))

    # One extra blueprint has it build from a diagonal matrix.
    @test ProducerCompetition.Diagonal <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = ProducerCompetition.Diagonal(; diag = 5, off = 8)
    @test bp.diag isa Float64
    @test bp.off isa Float64
    @test (bp.diag, bp.off) == (5, 8)
    @test bp == ProducerCompetition(; diag = 5, off = 8)
    @test bp == ProducerCompetition(; d = 5, o = 8) # ((quite) some aliases)
    @test bp == ProducerCompetition(; diagonal = 5, offdiagonal = 8)
    @test bp == ProducerCompetition(; d = 5, rest = 8)
    @test bp == ProducerCompetition(; d = 5, nondiagonal = 8)
    @test bp == ProducerCompetition(; d = 5, nd = 8)
    @test_repr(bp, "<ProducerCompetition>:Diagonal(diag: 5.0, off: 8.0)")
    @test_disp(bp,
        """
        blueprint for <ProducerCompetition>: Diagonal {
          diag: 5.0,
          off: 8.0,
        }\
        """)

    # Default values.
    bp = ProducerCompetition.Diagonal()
    @test bp == ProducerCompetition(; diag = 1, off = 0)
    @test bp == ProducerCompetition(; diag = 1)
    @test bp == ProducerCompetition(; off = 0)

    @argfails(ProducerCompetition.Diagonal(5), "Unexpected positional argument: 5  ::$Int")
    @argfails(ProducerCompetition.Diagonal(; x = 5), "Unexpected argument: x = 5.")

    #---------------------------------------------------------------------------------------
    # Early check.
    @bpfails(ProducerCompetition.Diagonal(; diag = -2),
        ProducerCompetition.Diagonal, :construct,
        (s, -2.0, :uwhole, "Value cannot be negative."))
    bp.off -= 5
    addfails.@check(base + bp, [],
        (ProducerCompetition.Diagonal, :early,
            (s, -5.0, :uwhole, "Value cannot be negative.")))
    # TODO: report field name instead. Introduce IT.fields_check(::Type{BP})?

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = ProducerCompetition.Diagonal(; diag = 7, off = 8)
    m = base + bp
    @test m.producers.competition == m.inter_producer.competition == [
        7 8 8
        8 7 8
        8 8 7
    ]

    addfails.@missing(Model(bp),
        Foodweb, ProducerCompetition, [ProducerCompetition.Diagonal], nothing)

end

end

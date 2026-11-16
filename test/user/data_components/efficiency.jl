module EfficiencyTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    D, @argfails, @test_repr, @test_disp, @bpfails, addfails
using Test

const d, _D = D.EdgeField(:trophic, :efficiency)

@testset "Efficiency component." begin

    @test Efficiency isa Component

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    # One extra blueprint has it build from the nature of trophic links.
    @test Efficiency.Miele2019 <: Blueprint

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = Efficiency.Miele2019(; e_herbivorous = 0.2, e_carnivorous = 0.4)
    @test bp.e_herbivorous isa Float64
    @test bp.e_carnivorous isa Float64
    @test bp == Efficiency.Miele2019(; herb = 0.2, carn = 0.4)
    @test bp == Efficiency(:Miele2019; e_herbivorous = 0.2, e_carnivorous = 0.4)
    @test bp == Efficiency(:Miele2019; herb = 0.2, carn = 0.4)
    @test_repr(bp, "<Efficiency>:Miele2019(e_herbivorous: 0.2, e_carnivorous: 0.4)")
    @test_disp(bp,
        """
        blueprint for <Efficiency>: Miele2019 {
          e_herbivorous: 0.2,
          e_carnivorous: 0.4,
        }\
        """)

    # Default values.
    bp = Efficiency.Miele2019()
    @test bp.e_herbivorous == 0.45
    @test bp.e_carnivorous == 0.85
    @test bp == Efficiency.Miele2019(; herb = 0.45)
    @test bp == Efficiency.Miele2019(; carn = 0.85)
    @test bp == Efficiency(:Miele2019; herb = 0.45)
    @test bp == Efficiency(:Miele2019; carn = 0.85)
    @test bp == Efficiency(:Miele2019)

    @argfails(Efficiency.Miele2019(0.2, 0.4),
        """
        Unexpected positional argument. Expected keyword arguments, for instance:
          e_carnivorous = 0.85 (or carn)
          e_herbivorous = 0.45 (or herb)\
        """)

    @argfails(Efficiency.Miele2019(; x = 5), "Unexpected argument: x = 5.")

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency(:Miele2019; herb = 2), Efficiency.Miele2019, :construct,
        (d, 2.0, :uwhole, "Value must belong to [0, 1]."))
    bp.e_carnivorous = 5
    addfails.@check(base + bp, [], # TODO: report field name instead of 'efficiency'?
        (Efficiency.Miele2019, :early,
            (d, 5.0, :uwhole, "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Expand depending on the underlying foodweb.

    bp = Efficiency.Miele2019(; herb = 0.2, carn = 0.4)
    m = base + bp
    @test has_component(m, Efficiency)
    @test m.efficiency == [
        0 4 2
        0 0 2
        0 0 0
    ] / 10
    @test m.efficiency === m.e # Alias.

    # The foodweb is therefore required for expansion.
    addfails.@missing(Model() + bp, Foodweb, Efficiency, [Efficiency.Miele2019], nothing)
end

end

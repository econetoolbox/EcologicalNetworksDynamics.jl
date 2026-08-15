module SpeciesTest

using EcologicalNetworksDynamics

using Test

@testset "Species component." begin

    # Nothing much specific to test about species,
    # which is a rather regular node class component.
    m = Model(Species([:a, :b, :c]))

    # There are aliases though.
    @test m.species.number == 3
    @test m.species.number == m.richness
    @test m.species.number == m.S
    @test m.species.number == m.species.richness

end

end

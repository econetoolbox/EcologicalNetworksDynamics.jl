module HandlingTimeTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, addfails
using Test

const s, S = SL.EdgeField(:trophic, :handling_time)

@testset "HandlingTime." begin

    @test HandlingTime isa Component

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    # One extra blueprint to build from body masses.
    @test HandlingTime.Miele2019 <: Blueprint
    bp = HandlingTime.Miele2019()

    m = base + BodyMass(; Z = 1) + bp
    @test m.trophic.handling_time == [
        0 3 3
        0 0 3
        0 0 0
    ] / 10

    addfails.@missing(base + bp, BodyMass, nothing, [HandlingTime.Miele2019], nothing)

end

end

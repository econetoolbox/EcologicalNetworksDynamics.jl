module CarryingCapacityTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, SparseVector, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:producers, :carrying_capacity)

@testset "CarryingCapacity." begin

    # Mostly duplicated from Growth.
    @test CarryingCapacity isa Component
    @bpfails(CarryingCapacity(-1),
        CarryingCapacity.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c], :b => :c]))
    m = base + CarryingCapacity([5, 8])
    @test m.K == m.carrying_capacity == m.producers.carrying_capacity == [5, 8]
    @test spextract(m.K) isa SparseVector{Float64}
    @test spextract(m.K) == [0, 0, 5, 8]

    # From temperature.
    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)
    bp = CarryingCapacity.Temperature(:Binzer2016)
    @test bp == CarryingCapacity(:Binzer2016)
    @test_repr(bp.allometry, "Allometry(p: (a: 3.0, b: 0.28), i: (), e: ())")
    m = base + Temperature(; celc = 20) + bp
    @test m.carrying_capacity ≈ [3, 3]

end

end

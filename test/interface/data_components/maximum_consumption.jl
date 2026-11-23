module MaximumConsumptionTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, SparseVector, @test_repr, @bpfails
using Test

const s, S = SL.NodeField(:consumers, :maximum_consumption)

@testset "MaximumConsumption." begin

    @test MaximumConsumption isa Component
    @bpfails(MaximumConsumption(-1),
        MaximumConsumption.Flat, :construct, (s, -1.0, :uwhole, "Value cannot be negative."))

    base = Model(Species("abcd"), Foodweb([:a => [:b, :c], :b => :c]))
    m = base + MaximumConsumption([5, 8])
    @test m.y == m.maximum_consumption == [5, 8]
    @test spextract(m.y) isa SparseVector{Float64}
    @test spextract(m.y) == [5, 8, 0, 0]

    # From allometry.
    base += BodyMass(; Z = 1) + MetabolicClass([:i, :e, :p, :p])
    bp = MaximumConsumption.Allometric(:Miele2019)
    @test bp == MaximumConsumption(:Miele2019)
    @test_repr(bp.allometry, "Allometry(p: (), i: (a: 8.0, b: 0.0), e: (a: 4.0, b: 0.0))")
    m = base + bp
    @test m.maximum_consumption ≈ [8, 4]
end

end

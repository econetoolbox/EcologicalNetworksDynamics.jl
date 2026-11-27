module ConsumerPreferenceTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests: SL, @test_repr, @test_disp
using Test

const s, S = SL.EdgeField(:trophic, :consumer_preference)

@testset "ConsumerPreference." begin

    @test ConsumerPreference isa Component

    base = Model(Foodweb([:a => [:b, :c], :b => [:c, :d, :e], :c => :d]))

    # One extra blueprint to build from the foodweb.
    @test ConsumerPreference.Homogeneous <: Blueprint

    bp = ConsumerPreference.Homogeneous()

    # (first representation tested without fields)
    @test_repr(bp, "<ConsumerPreference>:Homogeneous()")
    @test_disp(bp, "blueprint for <ConsumerPreference>: Homogeneous {}")

    m = base + bp
    @test m.w == m.consumers.preference == m.trophic.consumer_preference ==
          map(
              x -> x > 0 ? 1 / x : 0,
              [
                  0 2 2 0 0
                  0 0 3 3 3
                  0 0 0 1 0
                  0 0 0 0 0
                  0 0 0 0 0
              ],
          )
end

end

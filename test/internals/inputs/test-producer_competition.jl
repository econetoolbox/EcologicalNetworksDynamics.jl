module ProducerCompetition
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "Build LogisticGrowth with producer competition" begin
    foodweb = FoodWeb([0 0 0; 0 0 0; 0 1 0]; quiet = true)

    g = LogisticGrowth(foodweb) # Default behaviour.
    @test g.a == [1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 0.0]

    # Define competition matrix with a (named) tuple.
    for a in [(1, 2), (d = 1, nd = 2), (offdiag = 2, diag = 1), (diagonal = 1, rest = 2)]
        g = LogisticGrowth(foodweb; a) # Set inter-specific competition.
        # Competition terms are 0 for all αij involving non-producers
        @test g.a == [1.0 2.0 0.0; 2.0 1.0 0.0; 0.0 0.0 0.0]
    end

    # If invalid name(s) in named tuple an error is thrown.
    @test_throws ArgumentError LogisticGrowth(foodweb; a = (d = 1, wrong_name = 2))
    @test_throws ArgumentError LogisticGrowth(foodweb; a = (oops = 1, ooops = 2))

    # Custom competition matrix.
    my_competition_matrix = [1.0 1.0 0.0; 1.0 1.0 0.0; 0.0 0.0 0.0]
    g = LogisticGrowth(foodweb; a = my_competition_matrix)
    @test g.a == [1.0 1.0 0.0; 1.0 1.0 0.0; 0.0 0.0 0.0]

    # Should fail if non zero a for non-producers.
    message = "all(a[non_producer, :] .== 0)"
    @test_throws AssertionError(message) LogisticGrowth(
        foodweb,
        a = [1.0 1.0 0.0; 1.0 1.0 0.0; 1.0 0.0 0.0],
    )
    # Should fail if the `a` dimension does not match the size of the foodweb.
    message = "size(a) == (S, S)"
    @test_throws AssertionError(message) LogisticGrowth(
        foodweb,
        a = [1.0 0.0; 1.0 0.0; 0.0 0.0],
    )
    @test_throws AssertionError(message) LogisticGrowth(foodweb, a = [1.0 0.0; 1.0 0.0])
end

end

module TestModelParameters
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

@testset "Model parameters" begin
    A = [0 0 0; 1 0 0; 1 1 0]
    foodweb = FoodWeb(A)

    # Default.
    p = ModelParameters(foodweb)
    @test p.biorates.x == [0, 0.314, 0.314]
    @test p.biorates.r == [1, 0, 0]
    @test p.producer_growth.K == [1, nothing, nothing]
    @test p.network.A == sparse(A)
    @test typeof(p.functional_response) == BioenergeticResponse

    # Custom biorates.
    p = ModelParameters(foodweb; biorates = BioRates(foodweb; x = 1))
    @test p.biorates.x == [1, 1, 1] # changed
    @test p.biorates.r == [1, 0, 0] # unchanged
    @test p.producer_growth.K == [1, nothing, nothing] # unchanged
    @test p.network.A == sparse(A) # unchanged
    @test typeof(p.functional_response) == BioenergeticResponse # unchanged

    # Classic Functional Response.
    p = ModelParameters(foodweb; functional_response = ClassicResponse(foodweb))
    @test p.biorates.x == [0, 0.314, 0.314] # unchanged
    @test p.biorates.r == [1, 0, 0] # unchanged
    @test p.producer_growth.K == [1, nothing, nothing] # unchanged
    @test p.network.A == sparse(A) # unchanged
    @test typeof(p.functional_response) == ClassicResponse # changed

    # Linear Functional Response.
    p = ModelParameters(foodweb; functional_response = LinearResponse(foodweb))
    @test typeof(p.functional_response) == LinearResponse

    # Warning if not ClassicResponse and MultiplexNetwork.
    multiplex_network = MultiplexNetwork(foodweb)
    lresp = LinearResponse(multiplex_network)
    bresp = BioenergeticResponse(multiplex_network)
    cresp = ClassicResponse(multiplex_network)
    linmsg = "Non-trophic interactions for `$LinearResponse` are not supported. \
        Use a classical functional response instead: `$ClassicResponse`."
    biomsg = "Non-trophic interactions for `$BioenergeticResponse` are not supported. \
        Use a classical functional response instead: `$ClassicResponse`."
    @test_logs (:warn, linmsg) ModelParameters(
        multiplex_network,
        functional_response = lresp,
    )
    @test_logs (:warn, biomsg) ModelParameters(
        multiplex_network,
        functional_response = bresp,
    )
    @test_nowarn ModelParameters(multiplex_network, functional_response = cresp)
end

end

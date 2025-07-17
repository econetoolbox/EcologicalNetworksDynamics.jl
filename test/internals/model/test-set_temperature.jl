module Temperature
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

A = [0 0 0; 1 0 0; 0 1 0]
foodweb = FoodWeb(A)
foodweb.metabolic_class = ["producer", "invertebrate", "ectotherm vertebrate"]
foodweb.M = [1.0, 10.0, 10.0]
temp = 303.15 # Kelvin.

@testset "set temperature" begin
    # By default the functional response is 'bioenergetic',
    # activating the temperature dependence should throw an error.
    p = ModelParameters(foodweb)
    @test_throws ArgumentError set_temperature!(p, temp, ExponentialBA())

    # No temperature response.
    set_temperature!(p, temp, NoTemperatureResponse())
    @test p.environment.T == temp
    @test p.temperature_response == NoTemperatureResponse()


    # Exponential Boltzmann-Arrhenius temperature dependence
    p = ModelParameters(foodweb; functional_response = ClassicResponse(foodweb))
    set_temperature!(p, temp, ExponentialBA())
    @test p.environment.T == temp
    @test p.producer_growth.K ==
          exp_ba_vector_rate(foodweb, temp, exp_ba_carrying_capacity())
    @test p.biorates.r == exp_ba_vector_rate(foodweb, temp, exp_ba_growth())
    @test p.biorates.x == exp_ba_vector_rate(foodweb, temp, exp_ba_metabolism())
    @test p.functional_response.hₜ ==
          exp_ba_matrix_rate(foodweb, temp, exp_ba_handling_time())
    @test p.functional_response.aᵣ ==
          exp_ba_matrix_rate(foodweb, temp, exp_ba_attack_rate())
    @test typeof(p.temperature_response) == ExponentialBA
    @test p.temperature_response.r == exp_ba_growth()
    @test p.temperature_response.x == exp_ba_metabolism()
    @test p.temperature_response.aᵣ == exp_ba_attack_rate()
    @test p.temperature_response.hₜ == exp_ba_handling_time()
    @test p.temperature_response.K == exp_ba_carrying_capacity()
end

@testset "Exponential BA customisation in set_temperature" begin

    # Exponential Boltzmann-Arrhenius temperature dependence.
    p = ModelParameters(foodweb; functional_response = ClassicResponse(foodweb))
    set_temperature!(
        p,
        temp,
        ExponentialBA(; K = exp_ba_carrying_capacity(; aₚ = 10, bᵢ = 0.5)),
    )

    @test p.temperature_response.K ==
          ExponentialBAParams(10.0, nothing, nothing, 0.28, 0.28, 0.5, 0.0, 0.0, 0.0, 0.71)
    @test p.temperature_response.r == exp_ba_growth()
    @test p.temperature_response.x == exp_ba_metabolism()
    @test p.temperature_response.aᵣ == exp_ba_attack_rate()
    @test p.temperature_response.hₜ == exp_ba_handling_time()
    @test typeof(p.temperature_response) == ExponentialBA
end

end

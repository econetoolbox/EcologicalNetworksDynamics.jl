module TemperatureDependentRates
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

A = [0 0 0 0; 0 0 0 0; 1 0 0 0; 0 1 0 0]
foodweb = FoodWeb(A)
foodweb.metabolic_class = ["producer", "producer", "invertebrate", "ectotherm vertebrate"]
foodweb.M = [1.0, 1.0, 1.0, 10.0]
temp = 303.15 # temperature in Kelvin
boltz = 8.617e-5 # boltzmann constant
norm_t = 293.15 # normalisation temperature


@testset "Constructors for exponential Boltzmann-Arrhenius parameters" begin
    @test exp_ba_growth() ==
          ExponentialBAParams(exp(-15.68), 0, 0, -0.25, -0.25, -0.25, 0, 0, 0, -0.84)
    @test exp_ba_metabolism() == ExponentialBAParams(
        0,
        exp(-16.54),
        exp(-16.54),
        -0.31,
        -0.31,
        -0.31,
        0,
        0,
        0,
        -0.69,
    )
    @test exp_ba_handling_time() == ExponentialBAParams(
        0,
        exp(9.66),
        exp(9.66),
        -0.45,
        -0.45,
        -0.45,
        0.47,
        0.47,
        0.47,
        0.26,
    )
    @test exp_ba_attack_rate() == ExponentialBAParams(
        0,
        exp(-13.1),
        exp(-13.1),
        0.25,
        0.25,
        0.25,
        -0.8,
        -0.8,
        -0.8,
        -0.38,
    )
    @test exp_ba_carrying_capacity() ==
          ExponentialBAParams(3, nothing, nothing, 0.28, 0.28, 0.28, 0, 0, 0, 0.71)
end

@testset "Computing exponential Boltzmann-Arhennius rates" begin
    foodweb.metabolic_class[1] = "unknown class" # introduce wrong class
    @test_throws ArgumentError exp_ba_vector_rate(foodweb, temp, exp_ba_growth())
    foodweb.metabolic_class[1] = "producer" # restore class
    customparams = ExponentialBAParams(0, 1, 1, 0, 1, 0.5, 1, 1, 2, 0.5)
    ba = exp(0.5 * ((norm_t - temp) / (boltz * temp * norm_t))) ## boltmann arrhenius term
    @test boltzmann(0.5, temp) == ba
    @test exp_ba_vector_rate(foodweb, temp, customparams) ==
          [0, 0, 1 * 1.0^0.5 * ba, 1 * 10.0^1 * ba]
    @test exp_ba_vector_rate(foodweb, temp, exp_ba_growth()) ≈ [
        # a * M^b * boltz
        (exp(-15.68) * 1^-0.25 * exp(-0.84 * (norm_t - temp) / (boltz * temp * norm_t))),
        (exp(-15.68) * 1^-0.25 * exp(-0.84 * (norm_t - temp) / (boltz * temp * norm_t))),
        0,
        0,
    ]
    @test exp_ba_vector_rate(foodweb, temp, exp_ba_metabolism()) ≈ [
        0,
        0,
        (exp(-16.54) * 1^-0.31 * exp(-0.69 * (293.15 - temp) / (boltz * temp * norm_t))),
        (exp(-16.54) * 10^-0.31 * exp(-0.69 * (norm_t - temp) / (boltz * temp * norm_t))),
    ]
    actual_K = exp_ba_vector_rate(foodweb, temp, exp_ba_carrying_capacity())
    @test actual_K[1:2] ≈ Vector{Any}([
        (3 * 1^0.28 * exp(0.71 * (norm_t - temp) / (boltz * temp * norm_t))),
        (3 * 1^0.28 * exp(0.71 * (norm_t - temp) / (boltz * temp * norm_t))),
    ])
    @test actual_K[3:4] == [nothing, nothing]
    @test exp_ba_matrix_rate(foodweb, temp, customparams) ≈
          sparse([0 0 0 0; 0 0 0 0; (1*1^0.5*1^1*ba) 0 0 0; 0 (1*10^1*1^2*ba) 0 0])
    a = exp(9.66) * 1^-0.45 * 1^0.47 * exp(0.26 * (norm_t - temp) / (boltz * temp * norm_t))
    b =
        exp(9.66) *
        10^-0.45 *
        1^0.47 *
        exp(0.26 * (norm_t - temp) / (boltz * temp * norm_t))
    @test exp_ba_matrix_rate(foodweb, temp, exp_ba_handling_time()) ≈ sparse([
        0 0 0 0
        0 0 0 0
        a 0 0 0
        0 b 0 0
    ])
    a =
        exp(-13.1) *
        1^0.25 *
        1^-0.8 *
        exp(-0.38 * (norm_t - temp) / (boltz * temp * norm_t))
    b =
        exp(-13.1) *
        10^0.25 *
        1^-0.8 *
        exp(-0.38 * (norm_t - temp) / (boltz * temp * norm_t))
    @test exp_ba_matrix_rate(foodweb, temp, exp_ba_attack_rate()) ≈ sparse([
        0 0 0 0
        0 0 0 0
        a 0 0 0
        0 b 0 0
    ])
end

@testset "Helper functions for exponential BA rate computation" begin
    expected_paramsvec = (
        a = Union{Nothing,Float64}[1.0, 1.0, 0.0, 0.0],
        b = Union{Nothing,Float64}[10.0, 10.0, 1.2, 1.1],
        c = Union{Nothing,Float64}[2.0, 2.0, 2.2, 2.1],
        Eₐ = 5.0,
    )
    expBA_params = ExponentialBAParams(1, 0, 0, 10.0, 1.1, 1.2, 2.0, 2.1, 2.2, 5.0)
    @test exp_ba_params_to_vec(foodweb, expBA_params) == expected_paramsvec
end

@testset "Exponential Boltzmann-Arrhenius parameter customisation" begin
    @test exp_ba_growth(; aₚ = exp(-3.0)) == ExponentialBAParams(
        exp(-3.0),
        0.0,
        0.0,
        -0.25,
        -0.25,
        -0.25,
        0.0,
        0.0,
        0.0,
        -0.84,
    )
    @test exp_ba_metabolism(; aₑ = exp(-18), aᵢ = exp(-10)) == ExponentialBAParams(
        0.0,
        exp(-18),
        exp(-10),
        -0.31,
        -0.31,
        -0.31,
        0.0,
        0.0,
        0.0,
        -0.69,
    )
    @test exp_ba_handling_time(; bₚ = -0.2, cₑ = 0.7) == ExponentialBAParams(
        0.0,
        exp(9.66),
        exp(9.66),
        -0.2,
        -0.45,
        -0.45,
        0.47,
        0.7,
        0.47,
        0.26,
    )
    @test exp_ba_attack_rate(; bₑ = 0.8, cᵢ = -0.1, Eₐ = -1.0) == ExponentialBAParams(
        0.0,
        exp(-13.1),
        exp(-13.1),
        0.25,
        0.8,
        0.25,
        -0.8,
        -0.8,
        -0.1,
        -1.0,
    )
    @test exp_ba_carrying_capacity(; aₚ = 10, bᵢ = 0.5) ==
          ExponentialBAParams(10.0, nothing, nothing, 0.28, 0.28, 0.5, 0.0, 0.0, 0.0, 0.71)
end

end

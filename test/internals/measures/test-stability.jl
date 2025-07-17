module Stability
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using Statistics

@testset "temporal stability as CV" begin

    # Matrix with 0 columns and 0 rows to checks that functions can handle
    # timeseries with 0 species (0 rows) or 0 timesteps (0 columns)
    mc = Matrix(undef, 0, 3)
    mr = Matrix(undef, 3, 0)

    # Test mean Population stability
    cvspnan_check = [
        isnan(species_cv([0 0; 0 0]).mean),
        isnan(species_cv([0 0; 0 0]).mean),
        isnan(species_cv(mc).mean),
        isnan(species_cv(mr).mean),
        isnan(species_cv(mc).species),
        isnan(species_cv(mr).species),
        all(isnan.(species_cv([0 0; 0 0]).species)),
    ]
    @test all(cvspnan_check)

    @test species_cv([1 1; 1 1]).mean == species_cv([2 2; 2 2]).mean == 0
    @test species_cv([0 1; 1 0]; corrected = false).mean ==
          species_cv([0 0; 1 1]; corrected = false).mean ==
          std([0 1]; corrected = false) * 2 / (0.5 * 2)

    # Test synchrony
    @test all(isnan.(synchrony.(([0 0; 0 0], mc, mr))))
    @test synchrony([0 1; 1 0]) == synchrony([1 0; 0 1]) == 0.0
    @test synchrony([0 0; 1 1]; corrected = false) ==
          synchrony([0 0; 0 1]; corrected = false) ==
          1.0

    # Test CV decompostion in population statibility and synchrony
    mat = rand(10, 5)
    @test std(sum.(eachrow(mat)); corrected = false) / mean(sum.(eachrow(mat))) ≈
          species_cv(mat; corrected = false).mean * sqrt(synchrony(mat; corrected = false))
    @test community_cv(mat) ≈ species_cv(mat).mean * sqrt(synchrony(mat))

    @test all(isnan.(community_cv.(([0 0; 0 0], mc, mr))))

    foodweb = FoodWeb([0 0; 1 0]; Z = 1) # Two producers and one consumer
    params = ModelParameters(
        foodweb;
        functional_response = BioenergeticResponse(foodweb; h = 1.0),
    )
    sol = simulates(params, [0.25, 0.25]; tmax = 500, callback = nothing, t0 = 0)

    cv_com = coefficient_of_variation(sol; last = 100)
    cv_one_sp = coefficient_of_variation(sol; idxs = [1], last = 100)
    cv_one_sp2 = coefficient_of_variation(sol; idxs = [2], last = 100)

    # One species is fully synchronous with itself
    @test synchrony(sol; last = 100, idxs = [1], corrected = false) ≈
          coefficient_of_variation(
              sol;
              idxs = [1],
              last = 100,
              corrected = false,
          ).synchrony ≈
          synchrony(sol; idxs = "s1", last = 100, corrected = false) ≈
          1.0
    @test cv_one_sp2.synchrony ==
          synchrony(sol; idxs = [2], last = 100) ==
          synchrony(sol; idxs = "s2", last = 100)
    @test cv_one_sp2.synchrony ≈ 1.0 atol = 10^-12
    # Strongly oscillating predator-prey are not so synchronous:
    @test synchrony(sol; last = 100) == cv_com.synchrony <= 0.5

    @test cv_one_sp.species[1] ==
          cv_one_sp.species_mean ==
          cv_one_sp.community ==
          species_cv(sol; idxs = [1], last = 100).mean ==
          species_cv(sol; idxs = [1], last = 100).species[1] ==
          species_cv(sol; idxs = "s1", last = 100).mean ==
          species_cv(sol; idxs = "s1", last = 100).species[1]
    @test cv_one_sp.species[1] ≈ 2.0 atol = 10^-1

    # Test "dead" species removal with CV
    one_sp = simulates(params, [0.25, 0.0]; tmax = 500, callback = nothing, t0 = 0)
    cv_one_sp = coefficient_of_variation(one_sp; idxs = [1], last = 10, corrected = false)

    @test synchrony(one_sp; last = 10, corrected = false) ≈ cv_one_sp.synchrony ≈ 1.0

    cv_one_sp2 = coefficient_of_variation(one_sp; idxs = 2, last = 10)
    @test all(isnan.(values(cv_one_sp2)))

end

end

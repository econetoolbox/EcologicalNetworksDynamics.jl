module Zombies
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using Logging

# Test inspired by this issue:
# https://discourse.julialang.org/t/zombies-in-biological-ode-why-is-my-solver-not-sticking-to-zero/90409
@testset "No zombies, extinction are handled correctly." begin
    foodweb = FoodWeb([0 0 0; 1 0 0; 1 0 0])
    biorates = BioRates(foodweb; y = [0, 7.992, 8])
    params = ModelParameters(foodweb; biorates = biorates)
    B0 = [0.5, 0.5, 0.5]
    sol = simulates(
        params,
        B0;
        callback = ExtinctionCallback(1e-5, params, true),
        tmax = 300_000,
        verbose = false,
        compare_rtol = 1e-6,
    )
    @test keys(get_extinct_species(sol)) == Set([2])
    sol2 = sol[2, :] # trajectory of species 2 biomass
    idx_cb_triggered = findall(x -> 0 < x < 1e-5, sol2)
    @test length(idx_cb_triggered) == 1 # cb triggered only once (no zombies)
    idx_cb_triggered = idx_cb_triggered[1]
    # When callback is triggered previous and next state are saved
    # to identify unambiguously the discontinuity.
    # Then we have two time steps at t_discontinuity:
    # 1. 0 < B_going_extinct <= extinction_threshold (before the callback)
    # 2. B_going_extinct = 0 (after the callback)
    @test sol.t[idx_cb_triggered] == sol.t[idx_cb_triggered+1]
    @test all(sol2 .>= 0) # no anti-biomass
end

# Ensure that when an species already extinct species comeback to life (aka a zombie)
# when using an implicit solver, that no @info message are shown.
# For more information about zombies see these issues:
# https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/65
# https://discourse.julialang.org/t/zombies-in-biological-ode-why-is-my-solver-not-sticking-to-zero/90409
@testset "Do not print zombies." begin
    S = 30
    # These matrix + starting point produced the zombies we used for debugging #65.
    A = [
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1
        0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0
    ]
    init = [
        0.20197788416366613
        0.8181234057820772
        0.432414667236654
        0.737538804597418
        0.4441056817567385
        0.6486833607750618
        0.33114258572026944
        0.19722714662611995
        0.0791057046839041
        0.612069302966278
        0.4282259474057287
        0.9026812348371785
        0.16349990134726955
        0.8302586665749448
        0.3199423555202626
        0.250204183744282
        0.33580588330926364
        0.008489158577453915
        0.35298797729727605
        0.9916709312191103
        0.8947174024096461
        0.5214118849856493
        0.49231530433895
        0.7244175639014634
        0.28696885619096124
        0.8271460754005022
        0.8378667523897583
        0.7794348058497022
        0.07577469950082871
        0.8397441903791558
    ]
    fw = FoodWeb(A)
    functional_response = ClassicResponse(fw)
    params = ModelParameters(fw; functional_response)
    logger = TestLogger()
    with_logger(logger) do
        simulates(params, init; tmax = 1_000_000, verbose = true, compare_rtol = 1e-7)
    end
    # Test that the `simulate` @info messages never contain empty vector of new extinct
    # species.
    # Otherwise, this means that a zombies has appeared and triggered the @info message.
    @test length(logger.logs) > 0
    for log in logger.logs
        log.level == Logging.Info && @test !(occursin("[]", log.message))
    end
end

end

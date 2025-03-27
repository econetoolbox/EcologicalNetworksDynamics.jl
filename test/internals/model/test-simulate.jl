@testset "Simulate" begin

    # Set up.
    foodweb = FoodWeb([0 0; 1 0])
    params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0))

    # Solution converges.
    solution1 = simulates(params, [0.5, 0.5]; verbose = false)
    @test is_terminated(solution1)
    solution2 = simulates(params, [0.3, 0.3]; saveat = 0.25, tmax = 10, verbose = false)
    @test is_success(solution2)
    solution3 = simulates(params, [0.2, 0.2]; saveat = 0.5, tmax = 5, verbose = false)
    @test is_success(solution3)


    # Initial biomass.
    @test solution1.u[begin] == [0.5, 0.5]
    @test solution2.u[begin] == [0.3, 0.3]
    @test solution3.u[begin] == [0.2, 0.2]

    # Timesteps.
    @test all([t ∈ Set(solution2.t) for t in (0:0.25:10)])
    @test all([t ∈ Set(solution3.t) for t in (0:0.5:5)])

    # If biomass start at 0, biomass stay at 0.
    solution_null = simulates(params, [0.0, 0.0]; callback = nothing)
    @test all(hcat(solution_null.u...) .== 0)
    @test keys(get_extinct_species(solution_null)) == Set([1, 2])


    # Check against negative initial biomass values.
    foodweb = FoodWeb([0 0; 1 0])
    params = ModelParameters(foodweb)
    @test_throws ArgumentError simulates(params, [-1], verbose = false)
    @test_throws ArgumentError simulates(params, [0.1, -1], verbose = false)
    @test_nowarn simulates(params, [1, 0], verbose = false)


    # Verbose - Is there a log message to inform the user of species going extinct?
    foodweb = FoodWeb([0 0; 1 0])
    params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0))
    @test_nowarn simulates(params, [0.5, 1e-12], verbose = false)
    @test keys(get_extinct_species(simulates(params, [0.5, 1e-12]; verbose = false))) ==
          Set([2])
    logger = TestLogger()
    with_logger(logger) do
        simulates(params, [0.5, 1e-12]; verbose = true, tstops = [0.1], compare_rtol = 1e-6)
    end
    n_info = 0
    n_warn = 0
    for log in logger.logs
        if log.level == Logging.Info
            @test log.message == "Species [2] went extinct at time t = 0.1. \n\
                                 1 out of 2 species are extinct."
            n_info += 1
        elseif log.level == Logging.Warn
            # New with Julia 11?
            # Quick patch to address https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/171
            # Should be gone as the result of addressing https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/141.
            @test log.message ==
                  "Using arrays or dicts to store parameters of different types \
                   can hurt performance.\nConsider using tuples instead.\n"
            n_warn += 1
        else
            throw("Unexpected log: $log")
        end
    end
    @test n_info == 3
    @test n_warn == (VERSION >= v"1.11" ? 1 : 0)
    @test keys(
        get_extinct_species(
            simulates(params, [0.5, 1e-12]; verbose = true, tstops = [0.1]),
        ),
    ) == Set([2])


    # Extinction threshold
    ## Both species below extinction threshold
    solution =
        simulates(params, [1e-6]; extinction_threshold = 1e-5, tmax = 1, verbose = false)
    @test solution.u[end] == [0.0, 0.0] # both species have gone extinct
    @test keys(get_extinct_species(solution)) == Set([1, 2])
    ## One species below extinction thresold
    solution =
        simulates(params, [1, 1e-6]; extinction_threshold = 1e-5, tmax = 1, verbose = false)
    @test solution.u[end][2] == 0 # species 2 is extinct
    @test solution.u[end][1] > 0 # species 1 is alive
    @test keys(get_extinct_species(solution)) == Set([2])
    ## Provide a vector of extinction threshold (one threshold per species)
    solution = simulates(
        params,
        [1e-5];
        extinction_threshold = [1e-6, 1e-4],
        tmax = 1,
        verbose = false,
    )
    @test solution.u[end][2] == 0 # species 2 is extinct
    @test solution.u[end][1] > 0 # species 1 is alive
    @test keys(get_extinct_species(solution)) == Set([2])
    ## Error if extinction threshold is not a Number or an AbstractVector
    @test_throws TypeError simulates(params, [1]; extinction_threshold = Set([1e-5]))
end

@testset "Equivalence natural mortality and metabolic demand" begin
    foodweb = FoodWeb([0 0; 1 0]; Z = 50)
    F = ClassicResponse(foodweb; aᵣ = 1.0)
    params_xd = ModelParameters(foodweb; functional_response = F)
    total_loss = params_xd.biorates.x .+ params_xd.biorates.d
    biorates_x = BioRates(foodweb; x = total_loss, d = 0)
    biorates_d = BioRates(foodweb; d = total_loss, x = 0)
    params_x = ModelParameters(foodweb; functional_response = F, biorates = biorates_x)
    params_d = ModelParameters(foodweb; functional_response = F, biorates = biorates_d)
    out_xd = simulates(params_xd, [1])
    out_d = simulates(params_d, [1])
    out_x = simulates(params_x, [1])
    @test out_xd.u[end] ≈ out_x.u[end] ≈ out_d.u[end]
end

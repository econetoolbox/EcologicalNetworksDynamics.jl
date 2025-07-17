module Utils
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

@testset "filtering simulation" begin

    # Set up
    foodweb = FoodWeb([0 0; 0 0]; quiet = true)
    params = ModelParameters(foodweb)

    sim = simulates(params, [0, 0.5]; tmax = 20)

    @test round.(extract_last_timesteps(sim; last = "20.5%")) == [0.0 0.0; 1.0 1.0]

    # Test errors on sugar
    @test_throws(
        ArgumentError("The `last` argument, when given as a string, \
                       should end with character '%'"),
        extract_last_timesteps(sim; last = "15%5")
    )

    @test_throws(
        ArgumentError("Cannot extract -100.1% of the solution's timesteps: \
                       0% < `last` <= 100% must hold."),
        extract_last_timesteps(sim, last = "-100.1%")
    )

    @test_throws(
        ArgumentError("Cannot extract 0.0% of the solution's timesteps: \
                       0% < `last` <= 100% must hold."),
        extract_last_timesteps(sim, last = "0%")
    )

    # Test last as integer
    @test_throws(
        ArgumentError("Cannot extract 100 timesteps \
                       from a trajectory solution with only 12 timesteps. \
                       Consider decreasing the `last` argument value \
                       and/or specifying it as a percentage instead (e.g. `\"10%\"`)."),
        extract_last_timesteps(sim, last = 100)
    )

    @test_throws(
        ArgumentError("Cannot extract 0 timesteps. `last` should be a positive integer."),
        extract_last_timesteps(sim, last = 0)
    )
    @test_throws(
        ArgumentError("Cannot extract -10 timesteps. `last` should be a positive integer."),
        extract_last_timesteps(sim, last = -10)
    )

    @test_throws(
        ArgumentError("Cannot extract `last` from a floating point number. \
                       Did you mean \"4.5%\"?"),
        extract_last_timesteps(sim, last = 4.5)
    )

    @test_throws(
        ArgumentError("Cannot extract timesteps with `last=Any[]` of type Vector{Any}. \
                       `last` should be a positive integer \
                       or a string representing a percentage."),
        extract_last_timesteps(sim, last = [])
    )

    @test_warn(
        "0.001% of 12 timesteps correspond to 0 output lines: \
         an empty table has been extracted.",
        extract_last_timesteps(sim, last = ".001%")
    )
    @test_nowarn extract_last_timesteps(sim, last = ".001%", quiet = true)

    # Test species selection
    @test extract_last_timesteps(sim; last = "10%", idxs = ["s1"]) ==
          extract_last_timesteps(sim; last = "10%", idxs = "s1") ==
          [0.0;;]

    err_sp_msg = "Species [\"s3\"] are not found in the network. Any mispelling?"
    @test_throws(
        ArgumentError(err_sp_msg),
        extract_last_timesteps(sim; last = "10%", idxs = "s3")
    )
    @test_throws(
        ArgumentError(err_sp_msg),
        extract_last_timesteps(sim; last = "10%", idxs = ["s3"])
    )

    err_id_msg = "Cannot extract idxs [4] when there are 2 species."
    @test_throws(
        ArgumentError(err_id_msg),
        extract_last_timesteps(sim; last = "10%", idxs = 4)
    )

    @test_throws(
        ArgumentError(err_id_msg),
        extract_last_timesteps(sim; last = "10%", idxs = [2, 4])
    )

    @test size(extract_last_timesteps(sim; last = 1), 2) == 1
    @test size(extract_last_timesteps(sim; last = 10), 2) == 10
    @test extract_last_timesteps(sim; last = 10) isa AbstractMatrix
end

@testset "check extinction" begin

    check_last = Internals.check_last_extinction
    @test check_last(100; t = [100], species = ["s2"], last = 1) == true

    @test_warn(
        "With `last` = 2, a table has been extracted with the species [\"s2\"], \
         that went extinct at timesteps = [100]. Set `last` <= 1 to get rid of them.",
        check_last(100, t = [100], species = ["s2"], last = 2)
    )

    foodweb = FoodWeb([0 0; 1 0]; Z = 1) # Two producers and one co
    params = ModelParameters(
        foodweb;
        functional_response = BioenergeticResponse(foodweb; h = 1.0),
    )
    sol = simulates(params, [0.25, 0.25]; tmax = 500, callback = nothing, t0 = 0)
    @test isnothing(Internals.check_last_extinction(sol; last = 1))

end

end

# Check post-simulation utils.

using Random
Random.seed!(12)

#-------------------------------------------------------------------------------------------
@testset "Retrieve model from simulation result." begin

    m = default_model(Foodweb([:a => :b, :b => :c]))
    sol = simulate(m, 0.5, 500)

    # Retrieve model from the solution obtained.
    msol = get_model(sol)
    @test msol == m

    # The value we get is a fresh copy of the state at simulation time.
    @test msol !== m # *Not* an alias.

    # Cannot be corrupted afterwards from the original value.
    @test m.K[:c] == 1
    m.K[:c] = 2
    @test m.K[:c] == 2 # Okay to keep working on original value.
    @test msol.K[:c] == 1 # Still true: simulation was done with 1, not 2.

    # Cannot be corrupted afterwards from the retrieved value itself.
    msol.K[:c] = 3
    @test msol.K[:c] == 3 # Okay to work on this one: user owns it.
    @test get_model(sol).K[:c] == 1 # Still true.

end

module TestPostSimulation

using EcologicalNetworksDynamics
using Test
using Random
import ..Main: @argfails

Random.seed!(12)

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

@testset "Retrieve correct trajectory indices from simulation results" begin

    m = default_model(Foodweb([:a => :b, :b => :c]), Nutrients.Nodes(2))
    sol = simulate(m, 0.5, 500; N0 = 0.2)

    # Pick correct values within the trajectory.
    sp = get_species_indices(sol)
    nt = get_nutrients_indices(sol)
    @test sp == 1:3
    @test nt == 4:5
    @test sol.u[1][sp] == [0.5, 0.5, 0.5]
    @test sol.u[1][nt] == [0.2, 0.2]

end

function check_extinctions(actual, expected)
    @test keys(actual) == keys(expected)
    for (k, v) in actual
        @test round(v; digits = 2) ≈ expected[k]
    end
end

@testset "Retrieve extinct species." begin

    m = default_model(Foodweb([:a => :b, :b => :c]), Mortality([0, 1, 0]))
    sol = simulate(m, 0.5, 600; show_degenerated = false)
    ext = get_extinctions(sol)
    check_extinctions(ext, Dict([1 => 256.80, 2 => 484.07]))

end

@testset "Retrieve topology from simulation result." begin

    m = default_model(Foodweb([:a => :b, :b => :c]), Mortality([0, 1, 0]))
    # An information message is displayed in case the resulting topology is degenerated.
    sol = @test_logs (
        :info,
        """
        The biomass graph at the end of simulation contains degenerated species nodes:
        Connected component with 1 species:
          - /!\\ 1 isolated producer [:c]
        This message is meant to attract your attention \
        regarding the meaning of downstream analyses \
        depending on the simulated biomasses values.
        You can silent it with `show_degenerated=false`.""",
    ) simulate(m, 0.5, 600)
    top = get_topology(sol)

    # Only the producer remains in there.
    @test collect(live_species(top)) == [3]

    # Test on wider graph.
    m = default_model(
        Foodweb([:a => [:b, :c], :b => :d, :c => :d, :e => [:c, :f], :g => :h]),
        Mortality([
            :a => 0,
            :b => 0,
            # These three get extinct.
            :c => 1,
            :d => 10,
            :e => 1,
            :f => 0,
            :g => 0,
            :h => 0,
        ]),
    )
    sol = @test_logs (
        :info,
        """
        The biomass graph at the end of simulation contains 3 disconnected components:
        Connected component with 2 species:
          - /!\\ 2 starving consumers [:a, :b]
        Connected component with 1 species:
          - /!\\ 1 isolated producer [:f]
        Connected component with 2 species:
          - 1 producer [:h]
          - 1 consumer [:g]
        This message is meant to attract your attention \
        regarding the meaning of downstream analyses \
        depending on the simulated biomasses values.
        You can silent it with `show_degenerated=false`.""",
    ) simulate(m, 0.5, 100)
    ext = get_extinctions(sol)
    check_extinctions(ext, Dict(3 => 22.57, 4 => 23.17, 5 => 61.76))

    # Scroll back in time.
    check_extinctions(get_extinctions(sol; date = 60), Dict(3 => 22.57, 4 => 23.17))
    check_extinctions(get_extinctions(sol; date = 23), Dict(3 => 22.57))
    check_extinctions(get_extinctions(sol; date = 20), Dict())

    @argfails(
        get_extinctions(sol; date = 150),
        "Invalid date for a simulation in t = [0.0, 100.0]: 150."
    )

end

end

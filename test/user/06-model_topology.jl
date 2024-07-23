# Check topology-related utils.

@testset "Analyze biomass foodweb topology after species removals." begin

    m = Model(Foodweb([:a => [:b, :c], :b => :d, :c => :d, :e => [:c, :f], :g => :h]))
    g = m.topology

    # Sort to ease testing.
    sortadj(g) = sort(
        collect([pred => sort(collect(preys)) for (pred, preys) in trophic_adjacency(g)]),
    )

    @test sortadj(g) == [
        :a => [:b, :c],
        :b => [:d],
        :c => [:d],
        :d => [],
        :e => [:c, :f],
        :f => [],
        :g => [:h],
        :h => [],
    ]

    # This graph has two disconnected components.
    function check_components(g, n)
        dc = collect(disconnected_components(g))
        @test length(dc) == n
        dc
    end
    u, v = check_components(g, 2)
    #! format: off
    @test sortadj(u) == [
        :a => [:b, :c],
        :b => [:d],
        :c => [:d],
        :d => [],
        :e => [:c, :f],
        :f => [],
    ]
    @test sortadj(v) == [
        :g => [:h],
        :h => [],
    ]
    #! format: on

    # But no degenerated species yet.
    check_set(fn, tops, expected) =
        for top in tops
            @test Set(m.species_label.(fn(m, top))) == Set(expected)
        end
    check_set(isolated_producers, (g, u, v), [])
    check_set(starving_consumers, (g, u, v), [])

    # Removing species changes the situation.
    biomass = [name in "cg" ? 0 : 1 for name in "abcdefgh"]
    restrict_to_live_species!(g, biomass)

    # Now there are three disconnected components.
    u, v, w = check_components(g, 3)
    @test sortadj(u) == [:a => [:b], :b => [:d], :d => []]
    @test sortadj(v) == [:e => [:f], :f => []]
    @test sortadj(w) == [:h => []]

    # A few quirks appear regarding foreseeable equilibrium state.
    check_set(isolated_producers, (g, w), [:h])
    check_set(isolated_producers, (u, v), [])
    check_set(starving_consumers, (g, u, v, w), [])

    # The more extinct species the more quirks.
    remove_species!(g, :d)
    u, v, w = check_components(g, 3)
    @test sortadj(u) == [:a => [:b], :b => []]
    @test sortadj(v) == [:e => [:f], :f => []]
    @test sortadj(w) == [:h => []]
    check_set(isolated_producers, (g, w), [:h])
    check_set(starving_consumers, (g, u), [:a, :b])
    check_set(isolated_producers, (u, v), [])
    check_set(starving_consumers, (v, v), [])

    @argfails(
        restrict_to_live_species!(g, [1]),
        "The given topology indexes 8 species (3 removed), \
         but the given biomasses vector size is 1."
    )

    # Cannot resurrect species.
    @argfails(
        restrict_to_live_species!(g, ones(8)),
        "Species :c has been removed from this topology, \
         but its biomass is still above threshold: 1.0 > 0."
    )

    # Producers connected by nutrients are not considered isolated anymore,
    # and the corresponding topology is not anymore disconnected.
    m += Nutrients.Nodes([:u])
    g = m.topology
    @test length(collect(disconnected_components(g))) == 1

    # Obtaining starving consumers is possible on extinction,
    # but not isolated producers.
    biomass = [name in "bcg" ? 0 : 1 for name in "abcdefgh"]
    restrict_to_live_species!(g, biomass)
    u, v = check_components(g, 2)
    check_set(isolated_producers, (u, v), [])
    check_set(starving_consumers, (u,), [:a])
    check_set(starving_consumers, (v,), [])

    # Even if the very last producer is only connected to its nutrient source.
    biomass = [name in "h" ? 1 : 0 for name in "abcdefgh"]
    restrict_to_live_species!(g, biomass)
    u, = check_components(g, 1)
    check_set(isolated_producers, (u,), [])
    check_set(starving_consumers, (u,), [])

end

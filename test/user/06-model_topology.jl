# Check topology-related utils.

@testset "Basic topology queries." begin

    m = Model(
        Foodweb([:a => [:b, :c], :b => :d, :c => :d, :e => [:c], :f => :g]),
        Nutrients.Nodes(2),
    )
    g = m.topology

    remove_species!(g, :c)
    remove_species!(g, :f)

    @test n_live_species(g) == 5
    @test n_live_nutrients(g) == 2
    @test n_live_producers(m, g) == 2
    @test n_live_consumers(m, g) == 3

    sp(it) = m.species_label.(collect(it))
    nt(it) = m.nutrient_label.(collect(it))
    labs(str) = Symbol.(collect(str))
    @test sp(live_species(g)) == labs("abdeg")
    @test nt(live_nutrients(g)) == [:n1, :n2]
    @test sp(live_producers(m, g)) == labs("dg")
    @test sp(live_consumers(m, g)) == labs("abe")

end

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

import ..TestTopologies: check_display
@testset "Elided display." begin

    Random.seed!(12)
    foodweb = Foodweb(:niche; S = 50, C = 0.2)
    m = default_model(foodweb, Nutrients.Nodes(5))
#! format: off
    check_display(
      m.topology,
      "Topology(2 node types, 1 edge type, 55 nodes, 516 edges)",
   raw"Topology for 2 node types and 1 edge type with 55 nodes and 516 edges:
  Nodes:
    :species => [:s1, :s2, :s3, :s4, :s5, :s6, :s7, :s8, :s9, :s10, :s11, :s12, :s13, :s14, :s15, ..., :s50]
    :nutrients => [:n1, :n2, :n3, :n4, :n5]
  Edges:
    :trophic
      :s1 => [:s25, :s26, :s27, :s28, :s29, :s30, :s31, :s32, :s33, :s34, :s35, :s36, :s37, :s38, :s39, :s40]
      :s2 => [:s1, :s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s18, :s19, :s2, :s20, :s21, :s22, ..., :s9]
      :s3 => [:s1, :s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s18, :s19, :s2, :s20, :s21, :s22, ..., :s9]
      :s4 => [:s21, :s22, :s23, :s24, :s25, :s26, :s27, :s28, :s29, :s30, :s31, :s32]
      :s5 => [:s38, :s39, :s40, :s41, :s42]
      :s6 => [:s1, :s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s18, :s19, :s2, :s20, :s21, :s22, ..., :s9]
      :s7 => [:s37, :s38, :s39, :s40, :s41]
      :s8 => [:s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s3, :s4, :s5, :s6, :s7, :s8, :s9]
      :s9 => [:s23, :s24, :s25, :s26, :s27, :s28, :s29, :s30]
      :s10 => [:s12, :s13, :s14, :s15, :s16, :s17, :s18, :s19, :s20]
      :s11 => [:s28, :s29, :s30, :s31, :s32, :s33, :s34, :s35, :s36, :s37, :s38]
      :s12 => [:s18, :s19, :s20]
      :s13 => [:s13, :s14, :s15, :s16, :s17, :s18, :s19, :s20, :s21, :s22, :s23, :s24, :s25, :s26, :s27, ..., :s29]
      :s14 => [:s18, :s19, :s20, :s21, :s22, :s23, :s24, :s25, :s26, :s27, :s28, :s29, :s30, :s31]
      :s15 => [:s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s18, :s19, :s20, :s21, :s22, :s23, :s24, ..., :s9]
      :s16 => [:s23, :s24, :s25, :s26, :s27]
      ...
      :s50 => [:n1, :n2, :n3, :n4, :n5]",
    )
#! format: on

end

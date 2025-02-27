module TestModelTopology

using EcologicalNetworksDynamics
import Main.TestTopologies: check_display
using Test
using Random

@testset "Basic topology queries." begin

    m = Model(
        Foodweb([:a => [:b, :c], :b => :d, :c => :d, :e => [:c], :f => :g]),
        Nutrients.Nodes(2),
    )
    m += NontrophicInteractions.Refuge.Topology(; A = [:g => :c, :d => :g])

    g = m.topology
    @test n_live_species(g) == m.species.live.number == 7
    @test n_live_nutrients(g) == m.nutrients.live.number == 2

    g = get_topology(m; without_species = [:c, :f], without_nutrients = [:n1])
    @test n_live_species(g) == 5
    @test n_live_nutrients(g) == 1

    without = (; without_species = [:c, :f])
    @test n_live_producers(m; without...) == 2
    @test n_live_consumers(m; without...) == 3

    sp(it) = m.species.label.(collect(it))
    nt(it) = m.nutrients.label.(collect(it))
    labs(str) = Symbol.(collect(str))
    @test sp(live_species(g)) == labs("abdeg")
    @test nt(live_nutrients(g)) == [:n2]
    @test sp(live_producers(m; without...)) == labs("dg")
    @test sp(live_consumers(m; without...)) == labs("abe")

    #! format: off
    @test adjacency_matrix(g, :species, :trophic, :nutrients) == Bool[
        0
        0
        1
        0
        1;;
    ]
    #! format: on

    @test species_adjacency_matrix(g, :refuge) == Bool[
        0 0 0 0 0 # :a
        0 0 0 0 0 # :b (c pruned)
        0 0 0 0 1 # :d
        0 0 0 0 0 # :e (f pruned)
        0 0 0 0 0 # :g
    ]

    @test foodweb_matrix(g) == Bool[
        0 1 0 0 0
        0 0 1 0 0
        0 0 0 0 0
        0 0 0 0 0
        0 0 0 0 0
    ]

    @test foodweb_matrix(g; transpose = true) == Bool[
        0 0 0 0 0
        1 0 0 0 0
        0 1 0 0 0
        0 0 0 0 0
        0 0 0 0 0
    ]

    @test foodweb_matrix(g; prune = false) == Bool[
        0 1 0 0 0 0 0
        0 0 0 1 0 0 0
        0 0 0 0 0 0 0 # :c included
        0 0 0 0 0 0 0
        0 0 0 0 0 0 0
        0 0 0 0 0 0 0 # :f included
        0 0 0 0 0 0 0
    ]

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
    check_set(fn, tops, expected, indices...) =
        for top in tops
            @test Set(m.species.label.(fn(top, indices...))) == Set(expected)
        end
    prods = m.producers.indices
    cons = m.consumers.indices
    check_set(isolated_producers, (g, u, v), [], prods)
    check_set(starving_consumers, (g, u, v), [], prods, cons)

    # Removing species changes the situation.
    mask = [name in "cg" for name in "abcdefgh"]
    g = get_topology(m; without_species = mask)

    # Now there are three disconnected components.
    u, v, w = check_components(g, 3)
    @test sortadj(u) == [:a => [:b], :b => [:d], :d => []]
    @test sortadj(v) == [:e => [:f], :f => []]
    @test sortadj(w) == [:h => []]

    # A few quirks appear regarding foreseeable equilibrium state.
    check_set(isolated_producers, (g, w), [:h], prods)
    check_set(isolated_producers, (u, v), [], prods)
    check_set(starving_consumers, (g, u, v, w), [], prods, cons)

    # The more extinct species the more quirks.
    remove_species!(g, :d)
    u, v, w = check_components(g, 3)
    @test sortadj(u) == [:a => [:b], :b => []]
    @test sortadj(v) == [:e => [:f], :f => []]
    @test sortadj(w) == [:h => []]
    check_set(isolated_producers, (g, w), [:h], prods)
    check_set(starving_consumers, (g, u), [:a, :b], prods, cons)
    check_set(isolated_producers, (u, v), [], prods)
    check_set(starving_consumers, (v, v), [], prods, cons)

    # Producers connected by nutrients are not considered isolated anymore,
    # and the corresponding topology is not anymore disconnected.
    m += Nutrients.Nodes([:u])
    g = m.topology
    @test length(collect(disconnected_components(g))) == 1

    # Obtaining starving consumers is possible on extinction,
    # but not isolated producers.
    for name in "bcg"
        remove_species!(g, name)
    end
    u, v = check_components(g, 2)
    check_set(isolated_producers, (u, v), [], prods)
    check_set(starving_consumers, (u,), [:a], prods, cons)
    check_set(starving_consumers, (v,), [], prods, cons)

    # Even if the very last producer is only connected to its nutrient source.
    for name in "adef"
        remove_species!(g, name)
    end
    u, = check_components(g, 1)
    check_set(isolated_producers, (u,), [], prods)
    check_set(starving_consumers, (u,), [], prods, cons)

end

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

end

module Functioning
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals
using SparseArrays

@testset "Extraction of living species" begin

    foodweb = FoodWeb([0 0; 1 0])
    params = ModelParameters(foodweb)
    sol = simulates(params, [0.5, 0.5])

    @test living_species(sol) == (species = ["s1", "s2"], idxs = [1, 2])
    @test living_species(sol; idxs = 1) ==
          living_species(sol; idxs = [1]) ==
          living_species(sol; idxs = "s1") ==
          living_species(sol; idxs = ["s1"]) ==
          (species = ["s1"], idxs = [1])

    @test living_species(sol; idxs = 2) ==
          living_species(sol; idxs = [2]) ==
          living_species(sol; idxs = "s2") ==
          living_species(sol; idxs = ["s2"]) ==
          (species = ["s2"], idxs = [2])

    sol0 = simulates(params, [0, 0])

    @test living_species(sol0; quiet = true).idxs == living_species([0 0; 0 0]) == Int64[]
    @test living_species(sol0; quiet = true).species == String[]

end

@testset "Trophic structure" begin

    # With trophic levels
    net = [0 0; 1 0]
    tlvl = trophic_levels(net)
    @test max_trophic_level(tlvl) == 2.0
    @test mean_trophic_level(tlvl) == 1.5
    @test weighted_mean_trophic_level([2, 1], tlvl) == sum([2 / 3 * 1, 1 / 3 * 2])
    @test weighted_mean_trophic_level([1, 2], tlvl) == sum([1 / 3 * 1, 2 / 3 * 2])

    # With a vector of species biomass and a network
    ## Both species survived
    bm = [1, 1]
    @test max_trophic_level(bm, net) == 2.0
    @test weighted_mean_trophic_level(bm, tlvl) == mean_trophic_level(bm, net) == 1.5
    @test trophic_structure(bm, net) == (
        max = 2.0,
        mean = 1.5,
        weighted_mean = 1.5,
        alive_species = [1, 2],
        alive_trophic_level = [1.0, 2.0],
        alive_A = sparse(net),
    )

    ## Only one species survived
    bm1 = [1, 0]
    bm2 = [0, 1]
    @test max_trophic_level(bm1, net) ==
          max_trophic_level(bm2, net) ==
          weighted_mean_trophic_level(bm1, net) ==
          weighted_mean_trophic_level(bm2, net) ==
          mean_trophic_level(bm1, net) ==
          mean_trophic_level(bm2, net) ==
          1.0
    @test trophic_structure(bm1, net) == (
        max = 1.0,
        mean = 1.0,
        weighted_mean = 1.0,
        alive_species = [1],
        alive_trophic_level = [1.0],
        alive_A = sparse(net[[1], [1]]),
    )
    @test trophic_structure(bm2, net) == (
        max = 1.0,
        mean = 1.0,
        weighted_mean = 1.0,
        alive_species = [2],
        alive_trophic_level = [1.0],
        alive_A = sparse(net[[2], [2]]),
    )

    ## Zero species survived
    bm0 = [0, 0]
    @test all(
        isnan.([
            max_trophic_level(bm0, net),
            weighted_mean_trophic_level(bm0, net),
            mean_trophic_level(bm0, net),
        ]),
    )
    @test all(isnan.(values(trophic_structure(bm0, net))[1:3]))
    @test values(trophic_structure(bm0, net))[4:6] == (Any[], Any[], Any[])

    foodweb = FoodWeb([0 1 1; 0 0 0; 0 0 0])
    params = ModelParameters(foodweb)
    sim_zero = simulates(params, [0, 0, 0]; verbose = true)
    sim_three = simulates(params, [0.5, 0.5, 0.5]; verbose = true)

    @test_throws(
        ArgumentError("`trophic_structure()` operates at the whole network level, \
                       so it makes no sense to ask for particular species \
                       with anything other than `idxs = nothing`."),
        trophic_structure(sim_zero; last = 10, idxs = 2)
    )

    troph_zero = trophic_structure(sim_zero; quiet = true)
    troph_three = trophic_structure(sim_three)
    troph_three_nan = trophic_structure(sim_three; threshold = 1000)

    alive_keys = (:alive_species, :alive_A, :alive_trophic_level)
    nan_keys = (:max, :mean, :weighted_mean)
    @test all(isnan.(values(troph_zero[nan_keys])))
    @test all(isempty.(values(troph_zero[alive_keys])))
    @test all(isnan.(values(troph_three_nan[nan_keys])))
    @test all(isempty.(values(troph_three_nan[alive_keys])))

    @test troph_three[alive_keys] == (
        alive_species = [1, 2, 3],
        alive_A = foodweb.A,
        alive_trophic_level = [2.0, 1.0, 1.0],
    )
end

@testset "Producer growth rate" begin
    foodweb = FoodWeb([0 0; 0 0]; quiet = true)
    params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0))
    u0 = [0, 0.5] # Initial biomass.
    sol = simulates(params, u0)
    normal_growth = producer_growth(sol; last = 1)
    # If biomass equal to 0, growth rate equal to 0.
    @test normal_growth.all[normal_growth.species.=="s1"][1][1] ≈ 0.0

    # First growth rate should be equal to the LogisticGrowth with initial biomass.
    first_growth = producer_growth(sol; last = length(sol.t), quiet = true)
    model = get_parameters(sol)
    g = model.producer_growth # Producer growth function.
    @test isa(g, LogisticGrowth)
    @test first_growth.all[1, :][1] == g(1, u0, model) == 0
    @test first_growth.all[2, :][1] == g(2, u0, model) == 0.25

    # Growth rate should converge to 0 as B converges to K.
    @test first_growth.all[2, :][length(sol.t)] ≈ 0 atol = 10^-3

    # Growth rate is computed only for producers.
    foodweb = FoodWeb([1 0; 0 0]; quiet = true)
    params = ModelParameters(foodweb)
    sol = simulates(params, [0.5, 0.5])
    normal_growth = producer_growth(sol; last = 1)
    @test length(normal_growth.species) == 1
    @test length(normal_growth.mean) == length(normal_growth.std) == 1
end

@testset "Total biomass, species persistence, Hill numbers" begin
    foodweb = FoodWeb([0 0; 0 0]; quiet = true)
    params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0))

    sim_two_sp = simulates(params, [0.5, 0.5]; verbose = false)
    sim_one_sp = simulates(params, [0, 0.5]; verbose = false)
    sim_zero = simulates(params, [0, 0]; verbose = false)
    m0, m1, m2 = sim_zero, sim_one_sp, sim_two_sp

    # Total biomass should converge to K.
    tmp_K = get_parameters(m1).producer_growth.K[2]
    @test biomass(m1; last = 1).total ≈ tmp_K rtol = 0.001
    @test biomass(m1; last = 1).total ≈ tmp_K rtol = 0.001
    bm_two_sp = biomass(m2; last = 1)
    @test bm_two_sp.total == sum(bm_two_sp.species)
    @test bm_two_sp.total ≈ 2 atol = 0.001

    # Select sub-collection of species.
    @test biomass(m1; last = 1, idxs = [1]).species[1] ≈
          biomass(m1; last = 1, idxs = [1]).total

    @test biomass(m0; last = 2, quiet = true).total ≈ 0.0
    # Species richness is the binary equivalent of total_biomass.
    @test richness(m0; last = 2, quiet = true) ≈ 0.0

    # Weird but it is a feature
    @test species_persistence(m0; last = 2, quiet = true) ≈ 0.0

    @test richness(m2[:, end]) == richness(m2; last = 1) == 2

    @test richness(m1[:, end]) == richness(m1; last = 1) == 1

    @test richness(m0[:, end]) == richness(m0; last = 1) == 0

    # Other hill diversity numbers
    ## Shannon
    @test shannon_diversity(m2[:, end]) ==
          shannon_diversity(m2; last = 1) ==
          shannon_diversity([1, 1]) ==
          log(2)

    # 0 entropy if 1 species only
    @test shannon_diversity(m1[:, end]) ==
          shannon_diversity([1]) ==
          shannon_diversity(m2; idxs = 1) ==
          shannon_diversity(m2; idxs = "s1") ==
          shannon_diversity(m2; idxs = 2) ==
          shannon_diversity(m2; idxs = "s2") ==
          shannon_diversity(m1; last = 1) ==
          0.0

    shannan(m; kwargs...) = isnan(shannon_diversity(m; kwargs...))
    shannan_check = [
        # Not defined for 0 species
        shannan(m0[:, end]),
        shannan(m0; last = 1),
        shannan([0, 0]),
        shannan([1, 1]; threshold = 1),
    ]
    @test all(shannan_check)

    @test shannon_diversity(m1[:, end]) == shannon_diversity(m1; last = 1) ≈ 0.0 # 0 entropy if 1 species only

    ## Simpson
    @test simpson(m2[:, end]) ==
          simpson(m2; last = 1) ==
          simpson([1, 1]) ==
          1 / sum(2 .^ [1 / 2, 1 / 2])
    # 0.5 if 1 species only
    @test simpson(m1[:, end]) ==
          simpson(m1; last = 1) ==
          simpson(m2; idxs = 1) ==
          simpson(m2; idxs = "s1") ==
          simpson(m2; idxs = 2) ==
          simpson(m2; idxs = "s2") ==
          simpson([1]) ==
          1 / sum(2 .^ 1) ==
          0.5

    simpnan(m; kwargs...) = isnan(simpson(m; kwargs...))
    simpnan_check = [
        # Not defined for 0 species
        simpnan(m0[:, end]),
        simpnan(m0; last = 1),
        simpnan([0, 0]),
        simpnan([1, 1]; threshold = 1),
    ]
    @test all(simpnan_check)

    # Community evenness
    # Maximum equity of species biomass
    @test evenness(m2[:, end]) == evenness(m2; last = 1) == evenness([1, 1]) == 1.0
    evennan(m; kwargs...) = isnan(evenness(m; kwargs...))
    evennan_check = [
        # Should be NaN if 1 species
        evennan(m1[:, end]),
        evennan(m2; idxs = 1),
        evennan(m2; idxs = "s1"),
        evennan(m2; idxs = "s2"),
        evennan(m2; idxs = 2),
        evennan([1, 0]),
        evennan([2, 1]; threshold = 1),
        # Should be NaN if 0 species
        evennan(m0[:, end]),
        evennan(m0; last = 1),
        evennan([0, 0]),
        evennan([1, 1]; threshold = 1),
    ]
    @test all(evennan_check)
end

end

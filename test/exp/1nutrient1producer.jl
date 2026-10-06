# The released version of the package contained an error in the nutrient dynamic
# function, which had an extra producer biomass term. The tests therein ensure
# that the bug has been fixed, meaning that the nutrient dynamic is correct.
# In particular, the tests are based on a minimal model (one producer, one
# nutrient), so we can derive analytically expected nutrient concentration and
# producer biomass at equilibrium.

module TestNutrientProducer

using EcologicalNetworksDynamics
using Test

#-------------------------------------------------------------------------------------------
@testset "Nutrient intake: 1 producer – 1 nutrient." begin

    # Define model parameters.
    r, m, K = 1.0, 0.5, 1.0
    D, S, c = 0.25, 5.0, 0.1
    N_eq = m * K / (r - m)
    B_eq = D * (S - N_eq) / (c * m)
    @test N_eq ≈ 1.0
    @test B_eq ≈ 20.0

    # Generate the model.
    foodweb = Foodweb([0;;])
    nutrient = NutrientIntake(
        1;
        r = [r],
        turnover = D,
        supply = S,
        concentration = c,
        half_saturation = K,
    )
    mortality = Mortality([m])
    model = default_model(foodweb, nutrient, mortality)

    # Derivatives are cancels out at equilibrium.
    du = EcologicalNetworksDynamics.Internals.dudt([B_eq, N_eq], model._value)
    @test all(isapprox.(du, 0.0; atol = 1e-10))

    # Simulation converges to analytical equilibrium values.
    sol = simulate(model, [1.0], 2_000; N0 = [S])
    B_end, N_end = sol.u[end]
    @test B_end ≈ B_eq rtol = 1e-4
    @test N_end ≈ N_eq rtol = 1e-4

    # Extinction when S < N*: B* = 0, N* = S.
    S_ext = 0.5
    nutrient_ext = NutrientIntake(
        1;
        r = [r],
        turnover = D,
        supply = S_ext,
        concentration = c,
        half_saturation = K,
    )
    model_ext = default_model(foodweb, nutrient_ext, mortality)
    sol = simulate(model_ext, [1.0], 2_000; N0 = [S_ext])
    B_end, N_end = sol.u[end]
    @test B_end ≈ 0.0 atol = 1e-5
    @test N_end ≈ S_ext rtol = 1e-4
end

end

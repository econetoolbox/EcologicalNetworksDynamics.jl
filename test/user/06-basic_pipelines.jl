# Check the most simple uses of the package.
# Stability desired.

using Random
Random.seed!(12)

rtol = 1e-3 # We don't guarantee more yet.

#-------------------------------------------------------------------------------------------
@testset "Basic befault pipeline." begin

    fw = Foodweb([0 1 0; 0 0 1; 0 0 0])  # (inline matrix input)
    m = default_model(fw)
    B0 = [0.5, 0.5, 0.5]
    tmax = 500
    sol = simulate(m, B0, tmax)
    @test isapprox(
        sol.u[end],
        [0.6505703879774151, 0.1889414733543331, 0.4164973283173464];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "Basic pipeline à-la-carte." begin

    # Start from empty model.
    m = Model()

    # Add components one by one.
    add!(m, Foodweb([:a => :b, :b => :c])) # (named adjacency input)
    add!(m, BodyMass(; Z = 10))
    add!(m, MetabolicClass(:all_invertebrates))
    add!(m, BioenergeticResponse(; w = :homogeneous, half_saturation_density = 0.5))
    add!(m, LogisticGrowth(; r = 1, K = 1))
    add!(m, Metabolism(:Miele2019))
    add!(m, Mortality(0))

    # Simulate.
    sol = simulate(m, 0.5, 500) # (all initial values to 0.5, simulate up to t=500)
    @test isapprox(
        sol.u[end],
        [0.6505703879774151, 0.1889414733543331, 0.4164973283173464];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "All-in-constructor style." begin

    m = Model(
        Foodweb([:a => :b, :b => :c]),
        BodyMass(; Z = 10),
        MetabolicClass(:all_invertebrates),
        BioenergeticResponse(),
        LogisticGrowth(),
        Metabolism(:Miele2019),
        Mortality(0),
    )

    sol = simulate(m, [0.5, 0.5, 0.5], 500)
    @test isapprox(
        sol.u[end],
        [0.6505703879774151, 0.1889414733543331, 0.4164973283173464];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "Infix operator style." begin

    # Construct blueprints independently from each other.
    fw = Foodweb([:a => :b, :b => :c])
    bm = BodyMass(; Z = 10)
    mc = MetabolicClass(:all_invertebrates)
    be = BioenergeticResponse()
    lg = LogisticGrowth()
    mb = Metabolism(:Miele2019)
    mt = Mortality(0)

    # Expand them all into the global model.
    m = Model() + fw + bm + mc + be + lg + mb + mt
    # (this produces a system copy on every '+')

    sol = simulate(m, 0.5, 500)
    @test isapprox(
        sol.u[end],
        [0.6505703879774151, 0.1889414733543331, 0.4164973283173464];
        rtol,
    )


end

#-------------------------------------------------------------------------------------------
@testset "Basic non-default functional response." begin

    fw = Foodweb([ # (multiline matrix input)
        0 1 0
        0 0 1
        0 0 0
    ])

    # If provided, the default will not be used.
    m = default_model(fw, ClassicResponse())

    sol = simulate(m, 0.5, 500)
    @test isapprox(
        sol.u[end],
        [0.30245442377904147, 0.1507782858041653, 0.8351420883977096];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "Basic NTI pipeline." begin

    m = default_model(
        Foodweb([1 => 2, 2 => 3]),
        # Add one facilitation interaction randomly.
        Facilitation.Layer(; A = (L = 1,)),
    )

    sol = simulate(m, 0.5, 500)
    @test isapprox(
        sol.u[end],
        [0.3073034568564342, 0.15077826302332667, 0.8791058938977693];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "Multiple NTI layers." begin

    m = default_model(
        Foodweb([:a => (:b, :c), :d => (:b, :e), :e => :c]),
        # 2D aliased multiplex API.
        NontrophicLayers(;
            L_facilitation = 1,
            C_refuge = 0.8,
            n_links = (cpt = 2, itf = 2),
        ),
    )

    sol = simulate(m, 0.5, 500)
    @test isapprox(
        sol.u[end],
        [
            0.6871892011471322,
            0.24497058086035212,
            0.2034744714268744,
            0.0,
            0.00012545266696651692,
        ];
        rtol,
    )

end

#-------------------------------------------------------------------------------------------
@testset "Multiple NTI layers: indirect style." begin

    m = default_model(
        Foodweb([:a => (:b, :c), :d => (:b, :e), :e => :c]),
        ClassicResponse(),
    )

    # Create the layers so they can be worked on first.
    layers = nontrophic_layers(;
        L_facilitation = 1,
        C_refuge = 0.8,
        n_links = (cpt = 2, itf = 2),
    )

    # Access them with convenience aliases.
    m += layers[:facilitation] + layers[:c] + layers["ref"] + layers['i']

    sol = simulate(m, 0.5, 500)
    @test isapprox(
        sol.u[end],
        [
            0.6871892011471322,
            0.24497058086035212,
            0.2034744714268744,
            0.0,
            0.00012545266696651692,
        ];
        rtol,
    )

end

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
            half_saturation = K
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
            half_saturation = K
    )
    model_ext = default_model(foodweb, nutrient_ext, mortality)
    sol = simulate(model_ext, [1.0], 2_000; N0 = [S_ext])
    B_end, N_end = sol.u[end]
    @test B_end ≈ 0.0 atol = 1e-5
    @test N_end ≈ S_ext rtol = 1e-4
end

module TestNutrientSupply
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Nutrients supply component." begin

    # Mostly duplicated from Nutrients.Turnover.

    base = Model()

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Vector.
    sp = Nutrients.Supply([1, 2, 3])
    m = base + sp
    # Implies nutrients nodes.
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.supply == [1, 2, 3]
    @test typeof(sp) == Nutrients.Supply.Raw

    # Mapped input.
    ## Integer keys.
    sp = Nutrients.Supply([2 => 1, 3 => 2, 1 => 3])
    m = base + sp
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.supply == [3, 1, 2]
    @test typeof(sp) == Nutrients.Supply.Map
    ## Symbol keys.
    sp = Nutrients.Supply([:a => 1, :b => 2, :c => 3])
    m = base + sp
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:a, :b, :c]
    @test m.nutrients.supply == [1, 2, 3]
    @test typeof(sp) == Nutrients.Supply.Map

    # Editable property.
    m.nutrients.supply[1] = 2
    m.nutrients.supply[2:3] *= 10
    @test m.nutrients.supply == [2, 20, 30]

    # Scalar (requires nodes to expand).
    sp = Nutrients.Supply(2)
    m = base + Nutrients.Nodes(3) + sp
    @test m.nutrients.supply == [2, 2, 2]
    @test typeof(sp) == Nutrients.Supply.Flat
    @sysfails(
        Model(Nutrients.Supply(5)),
        Missing(Nutrients.Nodes, Nutrients.Supply, [Nutrients.Supply.Flat], nothing)
    )

    # Checked.
    @sysfails(
        Model(Nutrients.Nodes(3)) + Nutrients.Supply([1, 2]),
        Check(
            late,
            [Nutrients.Supply.Raw],
            "Invalid size for parameter 's': expected (3,), got (2,).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Input guards.

    @sysfails(
        Model(Nutrients.Supply([1, -2])),
        Check(early, [Nutrients.Supply.Raw], "Not a positive value: s[2] = -2.0.")
    )

    # Common ref checks from GraphDataInputs (not tested for every similar component).
    @sysfails(
        Model(Nutrients.Nodes(2)) + Nutrients.Supply([1 => 0.1, 3 => 0.2]),
        Check(
            late,
            [Nutrients.Supply.Map],
            "Invalid 'nutrient' node index in 's'. \
             Index does not fall within the valid range 1:2: [3] (0.2).",
        )
    )

    @sysfails(
        Model(Nutrients.Nodes(2)) + Nutrients.Supply([:a => 0.1, :b => 0.2]),
        Check(
            late,
            [Nutrients.Supply.Map],
            "Invalid 'nutrient' node label in 's'. \
             Expected either :n1 or :n2, got instead: [:a] (0.1).",
        )
    )

    @failswith(
        (m.nutrients.supply[1] = 'a'),
        WriteError("not a value of type Real", :(nutrients.supply), (1,), 'a')
    )

    @failswith(
        (m.nutrients.supply[2:3] *= -10),
        WriteError("Not a positive value: s[2] = -20.0.", :(nutrients.supply), (2,), -20.0)
    )

end

end

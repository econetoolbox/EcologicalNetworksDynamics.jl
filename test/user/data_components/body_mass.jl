@testset "Body mass component." begin

    base = Model()

    #---------------------------------------------------------------------------------------
    # Construct from raw values.

    # Vector.
    bm = BodyMass([1, 2, 3])
    m = base + bm
    # Implies species compartment.
    @test m.richness == 3
    @test m.species.names == [:s1, :s2, :s3]
    @test m.body_mass == [1, 2, 3] == m.M
    @test typeof(bm) == BodyMass.Raw

    # Mapped input.
    ## Integer keys.
    bm = BodyMass([2 => 1, 3 => 2, 1 => 3])
    m = base + bm
    @test m.richness == 3
    @test m.species.names == [:s1, :s2, :s3]
    @test m.body_mass == [3, 1, 2] == m.M
    @test typeof(bm) == BodyMass.Map
    ## Symbol keys.
    bm = BodyMass([:a => 1, :b => 2, :c => 3])
    m = base + bm
    @test m.richness == 3
    @test m.species.names == [:a, :b, :c]
    @test m.body_mass == [1, 2, 3] == m.M
    @test typeof(bm) == BodyMass.Map

    # Editable property.
    m.body_mass[1] = 2
    m.body_mass[2:3] .*= 10
    @test m.body_mass == [2, 20, 30] == m.M

    # Scalar (requires species to expand).
    bm = BodyMass(2)
    m = base + Species(3) + bm
    @test m.body_mass == [2, 2, 2] == m.M
    @test typeof(bm) == BodyMass.Flat
    @sysfails(Model(BodyMass(5)), Missing(Species, BodyMass, [BodyMass.Flat], nothing))

    # Checked.
    @sysfails(
        Model(Species(3)) + BodyMass([1, 2]),
        Check(
            late,
            [BodyMass.Raw],
            "Invalid size for parameter 'M': expected (3,), got (2,).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Construct from Z values and the trophic level.

    fw = Foodweb([:a => [:b, :c], :b => :c])

    bm = BodyMass(; Z = 2.8)

    m = base + fw + bm
    @test m.trophic.level == [2.5, 2, 1]
    @test m.body_mass == [2.8^1.5, 2.8, 1]

    @sysfails(Model(Species(2)) + bm, Missing(Foodweb, nothing, [BodyMass.Z], nothing))
    @sysfails(
        base + fw + BodyMass(; Z = -1.0),
        Check(
            late,
            [BodyMass.Z],
            "Cannot calculate body masses from trophic levels \
             with a negative value of Z: -1.0.",
        )
    )

    #---------------------------------------------------------------------------------------
    # Input guards.

    @argfails(BodyMass(), "Either 'M' or 'Z' must be provided to define body masses.")

    @failswith(BodyMass([1, 2], Z = 3.4), MethodError)

    @sysfails(
        Model(BodyMass([1, -2])),
        Check(early, [BodyMass.Raw], "not a positive value: M[2] = -2.0.")
    )

    # Common ref checks from GraphDataInputs (not tested for every similar component).
    @sysfails(
        Model(Species(2)) + BodyMass([1 => 0.1, 3 => 0.2]),
        Check(
            late,
            [BodyMass.Map],
            "Invalid 'species' node index in 'M'. \
             Index does not fall within the valid range 1:2: [3] (0.2).",
        )
    )

    @sysfails(
        Model(Species(2)) + BodyMass([:a => 0.1, :b => 0.2]),
        Check(
            late,
            [BodyMass.Map],
            "Invalid 'species' node label in 'M'. \
             Expected either :s1 or :s2, got instead: [:a] (0.1).",
        )
    )

    @failswith(
        (m.M[1] = -10),
        EN.Views.WriteError("not a positive value", :body_mass, 1, -10.0)
    )

    # Graphview-related tests live in "../02-graphviews.jl".

end

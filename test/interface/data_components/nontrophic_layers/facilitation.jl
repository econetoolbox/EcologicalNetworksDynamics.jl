# Copied and adapted from competition layer.
@testset "Facilitation layer." begin

    base = Model(Foodweb([:a => [:b, :c, :d]]))

    # ======================================================================================
    # Layer topology.

    # Query potential links.
    @test base.facilitation.potential_links.matrix == [
        0 1 1 1
        0 0 1 1
        0 1 0 1
        0 1 1 0
    ]
    @test base.facilitation.potential_links.number == 9

    #---------------------------------------------------------------------------------------
    # Construct from raw edges.

    fl = Facilitation.Topology([
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ])
    m = base + fl
    @test m.facilitation.links.matrix == [
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ]
    @test Facilitation.Topology([]) == Facilitation.Topology(; A = []) # Synonymous.
    @test typeof(fl) === Facilitation.Topology.Raw

    # Alternate adjacency input.
    fl = Facilitation.Topology([:b => :c, :c => [:b, :d], :d => :b])
    @test m.facilitation.links.matrix == (base + fl).facilitation.links.matrix
    @test typeof(fl) == Facilitation.Topology.Adjacency

    #---------------------------------------------------------------------------------------
    # Draw random links instead.
    Random.seed!(12)

    # From a number of links.
    fl = Facilitation.Topology(; L = 4, sym = false)

    # Stochastic expansion!
    m = base + fl
    @test m.facilitation.links.matrix == [
        0 0 0 0
        0 0 0 0
        0 1 0 1
        0 1 1 0
    ]
    # So, surprisingly:                        /!\
    @test (base + fl).facilitation.links.matrix != (base + fl).facilitation.links.matrix
    @test typeof(fl) == Facilitation.Topology.Random

    # Or from connectance.
    m = base + Facilitation.Topology(; C = 0.5)
    @test m.facilitation.links.matrix == [
        0 0 0 1
        0 0 0 1
        0 1 0 1
        0 0 0 0
    ]

    # ======================================================================================
    # Layer data.

    # Intensity.
    fi = Facilitation.Intensity(5)
    @test fi.eta == 5
    m = base + fi
    @test m.facilitation.intensity == 5
    # Modifiable.
    m.facilitation.intensity = 8
    @test m.facilitation.intensity == 8

    # Functional form.
    ff = Facilitation.FunctionalForm((x, dx) -> x - dx)
    m = base + ff
    @test m.facilitation.fn(4, 5) == -1
    # Modifiable.
    m.facilitation.fn = (x, dx) -> x + dx
    @test m.facilitation.fn(4, 5) == 9

    # ======================================================================================
    # Aggregate behaviour component.

    # (this needs more input for some (legacy?) reason)
    base += BodyMass(1) + MetabolicClass(:all_invertebrates)

    fl = Facilitation.Layer(; topology = [
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ], intensity = 5)
    @test typeof(fl) == Facilitation.Layer.Pack
    m = base + fl

    # All components brought at once.
    @test m.facilitation.links.number == 4
    @test m.facilitation.intensity == 5
    @test m.facilitation.fn(4, -5) == -16

    # From a number of links.
    fl = Facilitation.Layer(; A = (L = 4, sym = false), I = 8)

    # Sub-blueprints are all here.
    @test fl.topology.L == 4
    @test fl.topology.symmetry == false
    @test fl.intensity.eta == 8
    @test fl.functional_form.fn(5, -8) == -35

    # And bring them all.
    m = base + fl
    @test m.facilitation.links.number == 4
    @test m.facilitation.intensity == 8
    @test m.facilitation.fn(4, -5) == -16

    # ======================================================================================
    # Input guards.

    # Arguments.
    @argfails(Facilitation.Topology(), "No input given to specify facilitation links.")
    @argfails(Facilitation.Topology(; A = [], b = 5), "Unexpected argument: b = 5.")
    @argfails(
        Facilitation.Topology([]; A = []),
        "Redundant facilitation topology input.\n\
         Received both: Any[]\n\
         and          : Any[]"
    )

    @argfails(
        Facilitation.Topology(; n_links = 3, C = 0.5),
        "Cannot specify both connectance and number of links \
         for drawing random facilitation links. \
         Received both 'n_links' argument (3) and 'C' argument (0.5)."
    )

    # Can't specify outside potential links.
    @sysfails(
        base + Facilitation.Topology([
            1 0 0 0
            1 0 0 0
            1 0 0 0
            0 1 0 0
        ]),
        Check(
            late,
            [Facilitation.Topology.Raw],
            "Non-missing value found for 'A' at edge index [1, 1] (true), \
             but the template for 'potential facilitation link' \
             only allows values at the following indices:\n  \
             [(1, 2), (3, 2), (4, 2), (1, 3), (2, 3), (4, 3), (1, 4), (2, 4), (3, 4)]",
        )
    )

    @sysfails(
        base + Facilitation.Topology([:b => :a]),
        Check(
            late,
            [Facilitation.Topology.Adjacency],
            "Invalid 'consumer facilitation link' edge label in 'A': [:b, :a] (true). \
             Valid edges target labels for source [:b] in this template are:\n  [:c, :d]",
        )
    )

    #---------------------------------------------------------------------------------------
    # Random topology.

    # Runtime-check C XOR L.
    fl = Facilitation.Topology(; conn = 3)
    @test fl.C == 3
    fl.L = 4 # Compromise blueprint state!
    @test fl.L == 4
    @sysfails(
        base + fl,
        Check(
            early,
            [Facilitation.Topology.Random],
            "Both 'C' and 'L' specified on blueprint.",
        )
    )
    fl.C = fl.L = nothing
    @sysfails(
        base + fl,
        Check(
            early,
            [Facilitation.Topology.Random],
            "Neither 'C' or 'L' specified on blueprint.",
        )
    )

    # Further consistency checks.
    @sysfails(
        base + Facilitation.Topology(; L = 3, symmetry = true),
        Check(
            early,
            [Facilitation.Topology.Random],
            "Cannot draw L = 3 links symmetrically: pick an even number instead.",
        )
    )

    @sysfails(
        base + Facilitation.Topology(; L = 10),
        Check(
            late,
            [Facilitation.Topology.Random],
            "Cannot draw L = 10 facilitation links \
             with these 3 producers and 1 consumer (max: L = 9).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Invalid functional form.

    f(x) = "nok"
    @sysfails(
        base + Facilitation.FunctionalForm(f),
        Check(
            early,
            [Facilitation.FunctionalForm.Raw],
            "Facilitation layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
        )
    )

    @failswith(
        (m.facilitation.fn = f),
        WriteError(
            "Facilitation layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
            :(facilitation.fn),
            nothing,
            f,
        )
    )

    #---------------------------------------------------------------------------------------
    # Packed layer.

    # Cannot not bring bundled sub-components.
    @argfails(Facilitation.Layer(), "Missing input to initialize field :topology.")
    fl = Facilitation.Layer(; topology = [])
    fl.topology = nothing # Can't be unbrought if missing.
    @sysfails(
        base + fl,
        Missing(
            Facilitation.Topology,
            Facilitation.Layer,
            [Facilitation.Layer.Pack],
            nothing,
        )
    )
    @sysfails(
        base + Facilitation.Layer(; A = (L = 4, sym = true), F = nothing),
        Missing(
            Facilitation.FunctionalForm,
            Facilitation.Layer,
            [Facilitation.Layer.Pack],
            nothing,
        )
    )

    # Special-cased unimpliable topology.
    fl.topology = Facilitation.Topology
    @sysfails(
        base + fl,
        Add(CannotImplyConstruct, Facilitation.Topology, [Facilitation.Layer.Pack]),
    )

end

# Copied and adapted from competition layer.
@testset "Refuge layer." begin

    base = Model(Foodweb([:a => [:b, :c], :b => :d]))

    # ======================================================================================
    # Layer topology.

    # Query potential links.
    @test base.refuge.potential_links.matrix == [
        0 0 0 0
        0 0 0 0
        0 1 0 1
        0 1 1 0
    ]
    @test base.refuge.potential_links.number == 4

    #---------------------------------------------------------------------------------------
    # Construct from raw edges.

    rl = Refuge.Topology([
        0 0 0 0
        0 0 0 0
        0 1 0 1
        0 0 1 0
    ])
    m = base + rl
    @test m.refuge.links.matrix == [
        0 0 0 0
        0 0 0 0
        0 1 0 1
        0 0 1 0
    ]
    @test Refuge.Topology([]) == Refuge.Topology(; A = []) # Synonymous.
    @test typeof(rl) === Refuge.Topology.Raw

    # Alternate adjacency input.
    rl = Refuge.Topology([:c => [:b, :d], :d => :c])
    @test m.refuge.links.matrix == (base + rl).refuge.links.matrix
    @test typeof(rl) == Refuge.Topology.Adjacency

    #---------------------------------------------------------------------------------------
    # Draw random links instead.
    Random.seed!(12)

    # From a number of links.
    rt = Refuge.Topology(; L = 2, sym = false)

    # Stochastic expansion!
    m = base + rt
    @test m.refuge.links.matrix == [
        0 0 0 0
        0 0 0 0
        0 0 0 0
        0 1 1 0
    ]
    # So, surprisingly:                  /!\
    @test (base + rt).refuge.links.matrix != (base + rt).refuge.links.matrix
    @test typeof(rt) == Refuge.Topology.Random

    # Or from connectance.
    m = base + Refuge.Topology(; C = 0.5)
    @test m.refuge.links.matrix == [
        0 0 0 0
        0 0 0 0
        0 1 0 0
        0 0 1 0
    ]

    # ======================================================================================
    # Layer data.

    # Intensity.
    ri = Refuge.Intensity(5)
    @test ri.phi == 5
    m = base + ri
    @test m.refuge.intensity == 5
    # Modifiable.
    m.refuge.intensity = 8
    @test m.refuge.intensity == 8

    # Functional form.
    rf = Refuge.FunctionalForm((x, dx) -> x - dx)
    m = base + rf
    @test m.refuge.fn(4, 5) == -1
    # Modifiable.
    m.refuge.fn = (x, dx) -> x + dx
    @test m.refuge.fn(4, 5) == 9

    # ======================================================================================
    # Aggregate behaviour component.

    # (this needs more input for some (legacy?) reason)
    base += BodyMass(1) + MetabolicClass(:all_invertebrates)

    rl = Refuge.Layer(; topology = [
        0 0 0 0
        0 0 0 0
        0 1 0 1
        0 1 0 0
    ], intensity = 5)
    @test typeof(rl) == Refuge.Layer.Pack
    m = base + rl

    # All components brought at once.
    @test m.refuge.links.number == 3
    @test m.refuge.intensity == 5
    @test m.refuge.fn(4, -5) == -1

    # From a number of links.
    rl = Refuge.Layer(; A = (L = 3, sym = false), I = 8)

    # Sub-blueprints are all here.
    @test rl.topology.L == 3
    @test rl.topology.symmetry == false
    @test rl.intensity.phi == 8
    @test rl.functional_form.fn(5, -8) == -5 / 7

    # And bring them all.
    m = base + rl
    @test m.refuge.links.number == 3
    @test m.refuge.intensity == 8
    @test m.refuge.fn(4, -5) == -1

    # ======================================================================================
    # Input guards.

    # Arguments.
    @argfails(Refuge.Topology(), "No input given to specify refuge links.")
    @argfails(Refuge.Topology(; A = [], b = 5), "Unexpected argument: b = 5.")
    @argfails(
        Refuge.Topology([]; A = []),
        "Redundant refuge topology input.\n\
         Received both: Any[]\n\
         and          : Any[]"
    )

    @argfails(
        Refuge.Topology(; n_links = 3, C = 0.5),
        "Cannot specify both connectance and number of links \
         for drawing random refuge links. \
         Received both 'n_links' argument (3) and 'C' argument (0.5)."
    )

    # Can't specify outside potential links.
    @sysfails(
        base + Refuge.Topology([
            1 0 0 0
            1 0 0 0
            1 0 0 0
            0 1 0 0
        ]),
        Check(
            late,
            [Refuge.Topology.Raw],
            "Non-missing value found for 'A' at edge index [1, 1] (true), \
             but the template for 'potential refuge link' \
             only allows values at the following indices:\n  \
             [(3, 2), (4, 2), (4, 3), (3, 4)]",
        )
    )

    @sysfails(
        base + Refuge.Topology([:b => :a]),
        Check(
            late,
            [Refuge.Topology.Adjacency],
            "Invalid 'consumer refuge link' edge label in 'A': [:b, :a] (true). \
             This template allows no valid edge targets labels for source [:b].",
        )
    )

    #---------------------------------------------------------------------------------------
    # Random topology.

    # Runtime-check C XOR L.
    rl = Refuge.Topology(; conn = 3)
    @test rl.C == 3
    rl.L = 4 # Compromise blueprint state!
    @test rl.L == 4
    @sysfails(
        base + rl,
        Check(early, [Refuge.Topology.Random], "Both 'C' and 'L' specified on blueprint.")
    )
    rl.C = rl.L = nothing
    @sysfails(
        base + rl,
        Check(
            early,
            [Refuge.Topology.Random],
            "Neither 'C' or 'L' specified on blueprint.",
        )
    )

    # Further consistency checks.
    @sysfails(
        base + Refuge.Topology(; L = 3, symmetry = true),
        Check(
            early,
            [Refuge.Topology.Random],
            "Cannot draw L = 3 links symmetrically: pick an even number instead.",
        )
    )

    @sysfails(
        base + Refuge.Topology(; L = 5),
        Check(
            late,
            [Refuge.Topology.Random],
            "Cannot draw L = 5 refuge links \
             with these 2 producers and 3 preys (max: L = 4).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Invalid functional form.

    f(x) = "nok"
    @sysfails(
        base + Refuge.FunctionalForm(f),
        Check(
            early,
            [Refuge.FunctionalForm.Raw],
            "Refuge layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
        )
    )

    @failswith(
        (m.refuge.fn = f),
        WriteError(
            "Refuge layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
            :(refuge.fn),
            nothing,
            f,
        )
    )

    #---------------------------------------------------------------------------------------
    # Packed layer.

    # Cannot not bring bundled sub-components.
    @argfails(Refuge.Layer(), "Missing input to initialize field :topology.")
    rl = Refuge.Layer(; topology = [])
    rl.topology = nothing # Can't be unbrought if missing.
    @sysfails(
        base + rl,
        Missing(Refuge.Topology, Refuge.Layer, [Refuge.Layer.Pack], nothing)
    )
    @sysfails(
        base + Refuge.Layer(; A = (L = 4, sym = true), F = nothing),
        Missing(Refuge.FunctionalForm, Refuge.Layer, [Refuge.Layer.Pack], nothing)
    )

    # Special-cased unimpliable topology.
    rl.topology = Refuge.Topology
    @sysfails(base + rl, Add(CannotImplyConstruct, Refuge.Topology, [Refuge.Layer.Pack]),)

end

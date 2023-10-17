@testset "Competition layer." begin

    base = Model(Foodweb([:a => [:b, :c, :d]]))

    # ======================================================================================
    # Layer topology.

    # Query potential links.
    @test base.competition.potential_links.matrix == [
        0 0 0 0
        0 0 1 1
        0 1 0 1
        0 1 1 0
    ]
    @test base.competition.potential_links.number == 6

    #---------------------------------------------------------------------------------------
    # Construct from raw edges.

    cl = Competition.Topology([
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ])
    m = base + cl
    @test m.competition.links.matrix == [
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ]
    @test Competition.Topology([]) == Competition.Topology(; A = []) # Synonymous.
    @test typeof(cl) === Competition.Topology.Raw

    # Alternate adjacency input.
    cl = Competition.Topology([:b => :c, :c => [:b, :d], :d => :b])
    @test m.competition.links.matrix == (base + cl).competition.links.matrix
    @test typeof(cl) == Competition.Topology.Adjacency

    #---------------------------------------------------------------------------------------
    # Draw random links instead.
    Random.seed!(12)

    # From a number of links.
    ct = Competition.Topology(; L = 4, sym = false)

    # Stochastic expansion!
    m = base + ct
    @test m.competition.links.matrix == [
        0 0 0 0
        0 0 0 1
        0 1 0 1
        0 1 0 0
    ]
    # So, surprisingly:                       /!\
    @test (base + ct).competition.links.matrix != (base + ct).competition.links.matrix
    @test typeof(ct) == Competition.Topology.Random

    # Or from connectance.
    m = base + Competition.Topology(; C = 0.5)
    @test m.competition.links.matrix == [
        0 0 0 0
        0 0 0 1
        0 0 0 1
        0 1 1 0
    ]

    # ======================================================================================
    # Layer data.

    # Intensity.
    ci = Competition.Intensity(5)
    @test ci.gamma == 5
    m = base + ci
    @test m.competition.intensity == 5
    # Modifiable.
    m.competition.intensity = 8
    @test m.competition.intensity == 8

    # Functional form.
    cf = Competition.FunctionalForm((x, dx) -> x - dx)
    m = base + cf
    @test m.competition.fn(4, 5) == -1
    # Modifiable.
    m.competition.fn = (x, dx) -> x + dx
    @test m.competition.fn(4, 5) == 9

    # ======================================================================================
    # Aggregate behaviour component.

    # (this needs more input for some (legacy?) reason)
    base += BodyMass(1) + MetabolicClass(:all_invertebrates)

    cl = Competition.Layer(; topology = [
        0 0 0 0
        0 0 1 0
        0 1 0 1
        0 1 0 0
    ], intensity = 5)
    @test typeof(cl) == Competition.Layer.Pack
    m = base + cl

    # All components brought at once.
    @test m.competition.links.number == 4
    @test m.competition.intensity == 5
    @test m.competition.fn(4, -5) == 24

    # From a number of links.
    cl = Competition.Layer(; A = (L = 4, sym = false), I = 8)

    # Sub-blueprints are all here.
    @test cl.topology.L == 4
    @test cl.topology.symmetry == false
    @test cl.intensity.gamma == 8
    @test cl.functional_form.fn(5, -8) == 45

    # And bring them all.
    m = base + cl
    @test m.competition.links.number == 4
    @test m.competition.intensity == 8
    @test m.competition.fn(4, -5) == 24

    # ======================================================================================
    # Input guards.

    # Arguments.
    @argfails(Competition.Topology(), "No input given to specify competition links.")
    @argfails(Competition.Topology(; A = [], b = 5), "Unexpected argument: b = 5.")
    @argfails(
        Competition.Topology([]; A = []),
        "Redundant competition topology input.\n\
         Received both: Any[]\n\
         and          : Any[]"
    )

    @argfails(
        Competition.Topology(; n_links = 3, C = 0.5),
        "Cannot specify both connectance and number of links \
         for drawing random competition links. \
         Received both 'n_links' argument (3) and 'C' argument (0.5)."
    )

    # Can't specify outside potential links.
    @sysfails(
        base + Competition.Topology([
            1 0 0 0
            1 0 0 0
            1 0 0 0
            0 1 0 0
        ]),
        Check(
            late,
            [Competition.Topology.Raw],
            "Non-missing value found for 'A' at edge index [1, 1] (true), \
             but the template for 'potential competition link' \
             only allows values at the following indices:\n  \
             [(3, 2), (4, 2), (2, 3), (4, 3), (2, 4), (3, 4)]",
        )
    )

    @sysfails(
        base + Competition.Topology([:b => :a]),
        Check(
            late,
            [Competition.Topology.Adjacency],
            "Invalid 'consumer competition link' edge label in 'A': [:b, :a] (true). \
             Valid edges target labels for source [:b] in this template are:\n  [:c, :d]",
        )
    )

    #---------------------------------------------------------------------------------------
    # Random topology.

    # Runtime-check C XOR L.
    cl = Competition.Topology(; conn = 3)
    @test cl.C == 3
    cl.L = 4 # Compromise blueprint state!
    @test cl.L == 4
    @sysfails(
        base + cl,
        Check(
            early,
            [Competition.Topology.Random],
            "Both 'C' and 'L' specified on blueprint.",
        )
    )
    cl.C = cl.L = nothing
    @sysfails(
        base + cl,
        Check(
            early,
            [Competition.Topology.Random],
            "Neither 'C' or 'L' specified on blueprint.",
        )
    )

    # Further consistency checks.
    @sysfails(
        base + Competition.Topology(; L = 3, symmetry = true),
        Check(
            early,
            [Competition.Topology.Random],
            "Cannot draw L = 3 links symmetrically: pick an even number instead.",
        )
    )

    @sysfails(
        base + Competition.Topology(; L = 8),
        Check(
            late,
            [Competition.Topology.Random],
            "Cannot draw L = 8 competition links with only 3 producers (max: L = 6).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Invalid functional form.

    f(x) = "nok"
    @sysfails(
        base + Competition.FunctionalForm(f),
        Check(
            early,
            [Competition.FunctionalForm.Raw],
            "Competition layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
        )
    )

    @failswith(
        (m.competition.fn = f),
        WriteError(
            "Competition layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: f\n\
             with signature:   (Float64, Float64) -> Any[]",
            :(competition.fn),
            nothing,
            f,
        )
    )

    #---------------------------------------------------------------------------------------
    # Packed layer.

    # Cannot not bring bundled sub-components.
    @argfails(Competition.Layer(), "Missing input to initialize field :topology.")
    cl = Competition.Layer(; topology = [])
    cl.topology = nothing # Can't be unbrought if missing.
    @sysfails(
        base + cl,
        Missing(Competition.Topology, Competition.Layer, [Competition.Layer.Pack], nothing)
    )
    @sysfails(
        base + Competition.Layer(; A = (L = 4, sym = true), F = nothing),
        Missing(
            Competition.FunctionalForm,
            Competition.Layer,
            [Competition.Layer.Pack],
            nothing,
        )
    )

    # Special-cased unimpliable topology.
    cl.topology = Competition.Topology
    @sysfails(
        base + cl,
        Add(CannotImplyConstruct, Competition.Topology, [Competition.Layer.Pack]),
    )

end

module TestInterference
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

# Copied and adapted from competition layer.
@testset "Interference layer." begin

    base = Model(Foodweb([:a => [:b, :c], :b => :c, :d => [:b, :a]]))

    # ======================================================================================
    # Layer topology.

    # Query potential links.
    @test base.interference.potential_links.matrix == [
        0 1 0 1
        1 0 0 0
        0 0 0 0
        1 0 0 0
    ]
    @test base.interference.potential_links.number == 4

    #---------------------------------------------------------------------------------------
    # Construct from raw edges.

    il = Interference.Topology([
        0 0 0 1
        1 0 0 0
        0 0 0 0
        1 0 0 0
    ])
    m = base + il
    @test m.interference.links.matrix == [
        0 0 0 1
        1 0 0 0
        0 0 0 0
        1 0 0 0
    ]
    @test Interference.Topology([]) == Interference.Topology(; A = []) # Synonymous.
    @test typeof(il) === Interference.Topology.Raw

    # Alternate adjacency input.
    il = Interference.Topology([:a => :d, :b => :a, :d => :a])
    @test m.interference.links.matrix == (base + il).interference.links.matrix
    @test typeof(il) == Interference.Topology.Adjacency

    #---------------------------------------------------------------------------------------
    # Draw random links instead.
    Random.seed!(12)

    # From a number of links.
    it = Interference.Topology(; L = 2, sym = false)

    # Stochastic expansion!
    m = base + it
    @test m.interference.links.matrix == [
        0 1 0 0
        0 0 0 0
        0 0 0 0
        1 0 0 0
    ]
    # So, surprisingly:                        /!\
    @test (base + it).interference.links.matrix != (base + it).interference.links.matrix
    @test typeof(it) == Interference.Topology.Random

    # Or from connectance.
    m = base + Interference.Topology(; C = 0.5)
    @test m.interference.links.matrix == [
        0 1 0 0
        1 0 0 0
        0 0 0 0
        0 0 0 0
    ]

    # ======================================================================================
    # Layer data.

    # Intensity.
    ii = Interference.Intensity(5)
    @test ii.psi == 5
    m = base + ii
    @test m.interference.intensity == 5
    # Modifiable.
    m.interference.intensity = 8
    @test m.interference.intensity == 8

    # ======================================================================================
    # Aggregate behaviour component.

    # (this needs more input for some (legacy?) reason)
    base += BodyMass(1) + MetabolicClass(:all_invertebrates)

    il = Interference.Layer(; topology = [
        0 1 0 0
        1 0 0 0
        0 0 0 0
        1 0 0 0
    ], intensity = 5)
    @test typeof(il) == Interference.Layer.Pack
    m = base + il

    # All components brought at once.
    @test m.interference.links.number == 3
    @test m.interference.intensity == 5

    # From a number of links.
    il = Interference.Layer(; A = (L = 3, sym = false), I = 8)

    # Sub-blueprints are all here.
    @test il.topology.L == 3
    @test il.topology.symmetry == false
    @test il.intensity.psi == 8

    # And bring them all.
    m = base + il
    @test m.interference.links.number == 3
    @test m.interference.intensity == 8

    # ======================================================================================
    # Input guards.

    # Arguments.
    @argfails(Interference.Topology(), "No input given to specify interference links.")
    @argfails(Interference.Topology(; A = [], b = 5), "Unexpected argument: b = 5.")
    @argfails(
        Interference.Topology([]; A = []),
        "Redundant interference topology input.\n\
         Received both: Any[]\n\
         and          : Any[]"
    )

    @argfails(
        Interference.Topology(; n_links = 3, C = 0.5),
        "Cannot specify both connectance and number of links \
         for drawing random interference links. \
         Received both 'n_links' argument (3) and 'C' argument (0.5)."
    )

    # Can't specify outside potential links.
    @sysfails(
        base + Interference.Topology([
            1 0 0 0
            1 0 0 0
            1 0 0 0
            0 1 0 0
        ]),
        Check(
            late,
            [Interference.Topology.Raw],
            "Non-missing value found for 'A' at edge index [1, 1] (true), \
             but the template for 'potential interference link' \
             only allows values at the following indices:\n  \
             [(2, 1), (4, 1), (1, 2), (1, 4)]",
        )
    )

    @sysfails(
        base + Interference.Topology([:b => :c]),
        Check(
            late,
            [Interference.Topology.Adjacency],
            "Invalid 'consumer interference link' edge label in 'A': [:b, :c] (true). \
             Valid edges target labels for source [:b] in this template are:\n  [:a]",
        )
    )

    #---------------------------------------------------------------------------------------
    # Random topology.

    # Runtime-check C XOR L.
    il = Interference.Topology(; conn = 3)
    @test il.C == 3
    il.L = 4 # Compromise blueprint state!
    @test il.L == 4
    @sysfails(
        base + il,
        Check(
            early,
            [Interference.Topology.Random],
            "Both 'C' and 'L' specified on blueprint.",
        )
    )
    il.C = il.L = nothing
    @sysfails(
        base + il,
        Check(
            early,
            [Interference.Topology.Random],
            "Neither 'C' or 'L' specified on blueprint.",
        )
    )

    # Further consistency checks.
    @sysfails(
        base + Interference.Topology(; L = 3, symmetry = true),
        Check(
            early,
            [Interference.Topology.Random],
            "Cannot draw L = 3 links symmetrically: pick an even number instead.",
        )
    )

    @sysfails(
        base + Interference.Topology(; L = 6),
        Check(
            late,
            [Interference.Topology.Random],
            "Cannot draw L = 6 interference links \
             with these 3 consumers and 3 preys (max: L = 4).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Packed layer.

    # Cannot not bring bundled sub-components.
    @argfails(Interference.Layer(), "Missing input to initialize field :topology.")
    il = Interference.Layer(; topology = [])
    il.topology = nothing # Can't be unbrought if missing.
    @sysfails(
        base + il,
        Missing(
            Interference.Topology,
            Interference.Layer,
            [Interference.Layer.Pack],
            nothing,
        )
    )
    @sysfails(
        base + Interference.Layer(; A = (L = 4, sym = true), intensity = nothing),
        Missing(
            Interference.Intensity,
            Interference.Layer,
            [Interference.Layer.Pack],
            nothing,
        )
    )

    # Special-cased unimpliable topology.
    il.topology = Interference.Topology
    @sysfails(
        base + il,
        Add(CannotImplyConstruct, Interference.Topology, [Interference.Layer.Pack]),
    )

end

end

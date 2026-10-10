"Test all aspects of typical NodeField component, using body mass as an example."
module NodeFieldTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.NetworkFramework: EN, N, F, NF
using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @jl_basic_callfails, @checkfails, addfails, @bpfails,
    @viewfails, @mutfails
using OrderedCollections
using Test

@testset "Typical NodeField component" begin

    @test BodyMass isa Component # Etc.
    @test BodyMass.Z <: Blueprint # Extension point for extra BP worked, but test Z later.

    # ======================================================================================
    # From raw values.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = BodyMass.Raw([4.0, 5.0, 6.0])
    @test bp == BodyMass.Raw([4, 5, 6])
    @test bp == BodyMass([4.0, 5.0, 6.0])
    @test bp == BodyMass([4, 5, 6])
    @test BodyMass.Raw(Bool[1, 0, 1]) == BodyMass.Raw([1.0, 0.0, 1.0])
    @test BodyMass(Bool[1, 0, 1]) == BodyMass([1.0, 0.0, 1.0])
    @test bp == BodyMass.Raw(4, 5.0, 6)
    @test_repr(bp, "<BodyMass>:Raw(M: [4.0, 5.0, 6.0])")
    @test_disp(
        bp,
        """
        blueprint for <BodyMass>: Raw {
          M: [4.0, 5.0, 6.0],
        }\
        """
    )

    alias = bp.M
    @test alias === BodyMass.Raw(alias).M
    @test alias === BodyMass(alias).M

    invalid = [4, 5, :x]
    @bpfails(BodyMass.Raw(invalid),
        BodyMass.Raw, :construct,
        (nothing, 3, :convert, Float64, :x, "Conversion not implemented."))
    @checkfails(BodyMass(invalid), invalid,
        """
        Cannot convert input to either:
          - $Float64
          - $Vector{$Float64}
          - $OrderedDict{R, $Float64} where R
        (see attempts down the stacktrace)\
        """
    )

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(BodyMass([4, -5, 6]),
        BodyMass.Raw, :construct,
        (nothing, 2, :check, -5.0, "Value cannot be negative."))

    #---------------------------------------------------------------------------------------
    # Early check.

    alias[3] *= -1
    addfails.@check(Model(bp), [],
        (BodyMass.Raw, :early, (nothing, 3, :check, -6.0, "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("abc"), BodyMass([1, 2])), [],
        (BodyMass.Raw, :late,
            (:whole, :whole, :check, [1.0, 2.0],
                "Wrong number of values received for <species:body_mass>: \
                 expected 3, got 2.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    m = Model(bp)
    @test has_component(m, BodyMass)
    @test has_component(m, Species) # Implied.
    @test m.species.names == [:s1, :s2, :s3]
    @test_disp(m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 2 components:
          - Species: 3 (:s1, :s2, :s3)
          - BodyMass: [4.0, 5.0, 6.0]\
        """)

    # Would not override existing species names though.
    @test Model(Species("abc"), bp).species.names == [:a, :b, :c]

    # ======================================================================================
    # From mapped values.

    l = [:a => 4.0, :b => 5.0, :c => 6.0]
    li = [2 => 5.0, 3 => 6.0, 1 => 4.0]

    bp = BodyMass.Map(l)
    bpi = BodyMass.Map(li)
    @test bp == BodyMass.Map(['a' => 4, ("b", 0x5), [first(split("c")), 6//1]])
    @test bpi == BodyMass.Map([2 => 5, (3, 0x6), Any[1, 4//1]])
    @test bp == BodyMass(l)
    @test bpi == BodyMass(li)
    @test bp == BodyMass(Iterators.map(identity, l))
    @test bpi == BodyMass(Iterators.map(identity, li))
    @test_repr(bp, "<BodyMass>:Map(M: {a: 4.0, b: 5.0, c: 6.0})")
    @test_disp(
        bp,
        """
        blueprint for <BodyMass>: Map {
          M: {a: 4.0, b: 5.0, c: 6.0},
        }\
        """
    )

    for alias in (bp.M, bpi.M)
        @test BodyMass(alias).M === alias
    end

    @bpfails(BodyMass.Map([:a => [5, 8]]), BodyMass.Map, :construct,
        (nothing, :whole, :list,
            "Expected values of type 'Float64', \
             received instead at [1][right]: [5, 8]  ::$Vector{$Int}."))

    error("STOP HERE")
    # ======================================================================================
    # ↑ ↑ ↑ HERE update tests ↑ ↑ ↑
    # ======================================================================================

    # The values become available as a view.
    v = m.body_mass
    @test v isa View
    @test v isa AbstractVector{Float64}
    @test is_repr(v, "<species:body_mass>[4.0, 5.0, 6.0]")
    @test is_disp(
        v,
        """
        NodeFieldView<species:body_mass>{Float64} (3 values)
         4.0
         5.0
         6.0\
        """,
    )
    addfails.@missingrequired( # Unless the component is missing, as all properties.
        Model().body_mass,
        Property(body_mass, "Component $(EN._BodyMass) is required to read this property."),
    )

    # The view has some basic vector-like interface.
    @test v == collect(v) == [4, 5, 6] == [i for i in v]

    # The view may be extracted into a regular vector.
    e = extract(v)
    @test e isa Vector{Float64}
    @test e == v

    # Index with either integers or labels.
    @test v[1] == 4
    @test v[1:2] == [4, 5]
    @test v[(end-1):end] == [5, 6]
    @test v[:b] == 5
    @viewfails(
        v[nothing],
        View,
        "Views are indexed with indices (::Int) or labels (::Symbol). \
         Cannot index with: nothing ::Nothing."
    )
    @viewfails(v[0], View, "Cannot index with [0] into a class with 3 :species nodes.")
    @viewfails(v[4], View, "Cannot index with [4] into a class with 3 :species nodes.")
    @viewfails(
        v[:x],
        View,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c]."
    )
    @viewfails(v[], View, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2], View, "Cannot index into nodes with 2 dimensions: [1, 2].")

    # The field is *mutable* through the view.
    w = m.body_mass # Alternate view to the same model.
    alt = copy(m) # Forked model.
    a = alt.body_mass # Alternate view to the forked model.
    @test a == w == [4, 5, 6] # All synced (same underlying storage).

    # Mutate, invoking COW.
    v[1] *= 10
    v[:b] += 100
    @test v == w == m.body_mass == [40, 105, 6] # All views to model impacted, old and new.
    @test a == alt.body_mass == [4, 5, 6] # Forked model unchanged, or any view to it.

    # Support various mutating operations like regular julia arrays.
    v[1:2] .= 8
    v[(end-1):end] .*= 100
    @test v == w == m.body_mass == [8, 800, 600]
    @test a == alt.body_mass == [4, 5, 6]

    v .= [5, 4, 3]
    @test v == w == m.body_mass == [5, 4, 3]
    @test a == alt.body_mass == [4, 5, 6]

    # The value is still checked.
    @mutfails(
        v[2] = -1,
        "When attempting to mutate <species:body_mass> node field:\n\
         At node with label :b ([2]):\n\
         Value cannot be negative.\n\
         Received: -1.0"
    )
    @mutfails(
        v[:b] = -10,
        "When attempting to mutate <species:body_mass> node field:\n\
         At node with label :b ([2]):\n\
         Value cannot be negative.\n\
         Received: -10.0"
    )
    @mutfails(
        v .-= 4,
        "When attempting to mutate <species:body_mass> node field:\n\
         At node with label :c ([3]):\n\
         Value cannot be negative.\n\
         Received: -1.0"
    )

    # And all regular index guards are set.
    @viewfails(
        v[nothing] = 1,
        View,
        "Views are indexed with indices (::Int) or labels (::Symbol). \
         Cannot index with: nothing ::Nothing."
    )
    @viewfails(v[0] = 1, View, "Cannot index with [0] into a class with 3 :species nodes.")
    @viewfails(v[4] = 1, View, "Cannot index with [4] into a class with 3 :species nodes.")
    @viewfails(
        v[:x] = 1,
        View,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c]."
    )
    @viewfails(v[] = 1, View, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2] = 1, View, "Cannot index into nodes with 2 dimensions: [1, 2].")
    # Plus this mimick one.
    for invalid_set in (() -> v[1:2] = 8, () -> v[end:(end-1)] *= 10)
        @viewfails(
            invalid_set(),
            View,
            "Indexed assignment with a single value to possibly many locations \
             is not supported; perhaps use broadcasting `.=` instead?"
        )
    end

    # The field can also be pseudo-'reassigned', although this leaks no reference.
    m.body_mass = [6, 8, 4]
    @test m.body_mass == v == [6, 8, 4]

    # Reassignnment also works with mapped input.
    m.body_mass = Dict(:a => 2, :b => 3, :c => 7)
    @test m.body_mass == v == [2, 3, 7]

    # It may be partial/incomplete in this case.
    m.body_mass = Dict(:b => 100)
    @test m.body_mass == v == [2, 100, 7]

    # Or anything that could be used as a typical blueprint constructor.
    m.body_mass = 5
    @test m.body_mass == v == [5, 5, 5]

    # Checked.
    @mutfails(
        m.body_mass = [6, -1, 4],
        "When attempting to assign to <species:body_mass> node field:\n\
         At node index [2]:\n\
         Value cannot be negative.",
        -1,
    )
    @mutfails(
        m.body_mass = Dict(:a => 2, :x => 5, :c => 7),
        "When attempting to assign to <species:body_mass> node field:\n\
         Not a :species name: :x.",
    )
    @mutfails(
        m.body_mass = -1,
        "When attempting to assign to <species:body_mass> node field:\n\
         Value cannot be negative.",
        -1,
    )
    @mutfails(
        m.body_mass = :what,
        "When attempting to assign to <species:body_mass> node field:\n\
         Cannot convert input to either:\n  \
          - $Float64\n  \
          - $(Vector{Float64})\n  \
          - $(Map{Float64})",
        :what,
    )

    # Construct from mapped values.
    map = [:a => 4, :b => 5, :c => 6]
    bp = BodyMass.Map(map)
    @test bp == BodyMass(map) # Directly dispatched from component.
    @test is_repr(bp, "<BodyMass>:Map(M: {a: 4.0, b: 5.0, c: 6.0})")
    @test is_disp(
        bp,
        """
        blueprint for <BodyMass>: Map {\n  \
          M: {a: 4.0, b: 5.0, c: 6.0},\n\
        }\
        """,
    )
    # Expand into the same component.
    m = Model(bp)
    @test m.species.names == [:a, :b, :c]
    @test m.body_mass == [4, 5, 6]

    # Late-check against node names.
    m = Model(Species(m.species.names))
    addfails.@missingrequired(
        m + BodyMass([:a => 5, :x => 6, :y => 7]),
        Check(
            late,
            [BodyMass.Map],
            "When checking <species:body_mass> blueprint against model:\n\
             Missing for <species:body_mass>, no value provided for :b and :c.",
        )
    )
    addfails.@check(
        m + BodyMass([:a => 5, :b => 6, :c => 7, :x => 8, :y => 9]),
        Check(
            late,
            [BodyMass.Map],
            "When checking <species:body_mass> blueprint against model:\n\
             Not :species names: :x and :y.",
        )
    )
    # NOTE: Late checking of *values* is also performed,
    # but irrelevant for body_mass so not tested here.
    # Instead, they are tested at metabolic_class.

    # Same with index references.
    imap = [1 => 4, 2 => 5, 3 => 6]
    bp = BodyMass.Map(imap)
    @test bp == BodyMass(imap)
    @test is_repr(bp, "<BodyMass>:Map(M: {1: 4.0, 2: 5.0, 3: 6.0})")
    @test is_disp(
        bp,
        """
        blueprint for <BodyMass>: Map {\n  \
          M: {1: 4.0, 2: 5.0, 3: 6.0},\n\
        }\
        """,
    )
    m = Model(bp)
    @test m.species.names == [:s1, :s2, :s3] # Default names obtained.
    @test m.body_mass == [4, 5, 6]
    m = Model(Species(m.species.number))
    addfails.@missingrequired(
        m + BodyMass([1 => 5, 4 => 6, 5 => 7]),
        Check(
            late,
            [BodyMass.Map],
            "When checking <species:body_mass> blueprint against model:\n\
             Missing for <species:body_mass>, no value provided for nodes 2 and 3.",
        )
    )
    addfails.@check(
        m + BodyMass([1 => 5, 2 => 6, 3 => 7, 4 => 8, 5 => 9]),
        Check(
            late,
            [BodyMass.Map],
            "When checking <species:body_mass> blueprint against model:\n\
             Invalid indices for class :species with 3 nodes: 4 and 5.",
        )
    )

    # Alias blueprints if exact input type is used.
    bp = BodyMass.Map(map)
    input = bp.M
    bp = BodyMass(input)
    @test bp.M === input
    input[:x] = 15
    @test bp.M == OrderedDict([:a => 4, :b => 5, :c => 6, :x => 15])
    input[:x] *= -1
    addfails.@check(
        Model(bp),
        Check(
            early,
            [BodyMass.Map],
            "When checking <species:body_mass> blueprint data:\n\
             At node with label :x:\n\
             Value cannot be negative.\n\
             Received: -15.0",
        )
    )

    # Fail constructing from mapped.
    @bpfails(
        BodyMass.Map([:a => :what]),
        "When constructing <species:body_mass> from map:\n\
         Expected values of type '$Float64', \
         received instead at [1][right]: :what ::Symbol.",
    )

    # Construct from a flat value.
    bp = BodyMass.Flat(3)
    @test bp == BodyMass(3)
    m = Model(Species(5), bp)
    @test m.body_mass == [3, 3, 3, 3, 3]
    bp.M *= -1 # Mutable.
    addfails.@check(
        Model(Species(5), bp),
        Check(
            early,
            [BodyMass.Flat],
            "When checking <species:body_mass> blueprint data:\n\
             Value cannot be negative.\n\
             Received: -3.0",
        )
    )
    # But then it needs the class.
    addfails.@missingrequired(
        Model(bp),
        Missing(Species, nothing, [BodyMass.Flat], nothing)
    )

    # Fail constructing from Flat.
    @bpfails(
        BodyMass.Flat(:what),
        "When constructing <species:body_mass> from a flat value",
        :what,
        Float64,
        "Conversion not implemented.",
    )

    # Generic construction failure.
    @bpfails(
        BodyMass(:what),
        "Cannot convert input to either:\n  \
          - $Float64\n  \
          - $(Vector{Float64})\n  \
          - $(Map{Float64})",
        :what,
    )

end

end

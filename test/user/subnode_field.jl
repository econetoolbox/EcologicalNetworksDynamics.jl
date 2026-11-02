"Test all aspects of typical SubnodeField component, using producer growth as an example."
module SubnodeFieldTest

# Much inspired by `NodeField`.

using EcologicalNetworksDynamics
using SparseArrays

using EcologicalNetworksDynamics.NetworkFramework: EN, N, F, D, Views
using EcologicalNetworksDynamics.Tests:
    @test_disp, @test_repr, @argfails, @viewfails, addfails, @bpfails, @propfails,
    @mutfails, @checkfails, @test_err
using OrderedCollections
using Test

const d, _D = D.SubnodeField(:producers, :growth, :species)
const Pr = F.@PropertySpace(producers, N.Network)
const View = Views.SubnodeFieldView{d,Float64}

@testset "SubnodeField component: blueprints" begin

    @test GrowthRate isa EN.Component
    @test_disp(GrowthRate,
        """
        GrowthRate (component for $(N.Network), expandable from:
          Raw: raw values,
          Map: [producers => growth] map,
          Flat: uniform value,
          Allometric: allometric rates,
          Temperature: allometric rates and activation energy,
        )\
        """,
    )

    # Growth rate is only defined / can only be set for producers.
    base = Model(Foodweb([:a => :b, :c => (:b, :d)]))
    @test base.producers.mask == [0, 1, 0, 1]

    # ======================================================================================
    # From raw values.

    #---------------------------------------------------------------------------------------
    # Construct.
    # Careful: 'Raw' means 1 value per node in the subclass, not the parent.

    bp = GrowthRate.Raw([5.0, 8.0])
    @test bp.growth == [5, 8]
    @test bp.growth isa Vector{Float64}
    @test bp == GrowthRate([5, 8]) # Default construct.
    @test_repr(bp, "<GrowthRate>:Raw(growth: [5.0, 8.0])")
    @test_disp(bp,
        """
        blueprint for <GrowthRate>: Raw {
          growth: [5.0, 8.0],
        }\
        """)

    alias = bp.growth
    @test alias === GrowthRate.Raw(alias).growth
    @test alias == GrowthRate(alias).growth

    @checkfails(GrowthRate(5im), d, 5im, :uwhole,
        """
        Cannot convert input to either:
          - $Float64
          - $Vector{$Float64}
          - $OrderedDict{R, $Float64} where R
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    for invalid in [
        () -> GrowthRate.Raw([5, -8]),
        () -> GrowthRate([5, -8]),
    ]
        @bpfails(invalid(),
            GrowthRate.Raw, :construct, (d, -8.0, (:u, (2,)), "Value cannot be negative."))
    end

    alias[2] *= -10
    addfails.@check(base + bp, [],
        (GrowthRate.Raw, :early, (d, -80.0, (:u, (2,)), "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    bp.growth = [4, 5, 6]
    addfails.@check(base + bp, [],
        (GrowthRate.Raw, :late,
            (d, [4.0, 5.0, 6.0], :mwhole,
                "Wrong number of values received: expected 2, got 3.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = GrowthRate([5, 8])
    m = base + bp
    @test_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 3 links, 2 producers, 2 consumers, 2 preys, 2 tops.
          - GrowthRate: [·, 5.0, ·, 8.0]\
        """,
    )

    addfails.@missing(Model(bp), Foodweb, GrowthRate, [GrowthRate.Raw], nothing)

    # ======================================================================================
    # From mapped values.

    l = [:b => 5, :d => 8]
    li = [2 => 5.0, 4 => 8.0] # Not checked for density: targets *parent* species.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = GrowthRate.Map(l)
    bpi = GrowthRate.Map(li)

    @test bp.growth isa OrderedDict{Symbol,Float64}
    @test bpi.growth isa OrderedDict{Int,Float64}
    @test bp == GrowthRate.Map(['b' => 5, [first(split("d")), 8//1]])
    @test bpi == GrowthRate.Map([2 => 5, Any[4, 8//1]])
    @test bp == GrowthRate(l)
    @test bpi == GrowthRate(li)
    @test bp == GrowthRate(Iterators.map(identity, l))
    @test bpi == GrowthRate(Iterators.map(identity, li))
    @test_repr(bp, "<GrowthRate>:Map(growth: {b: 5.0, d: 8.0})")
    @test_disp(
        bp,
        """
        blueprint for <GrowthRate>: Map {
          growth: {b: 5.0, d: 8.0},
        }\
        """
    )

    for alias in (bp.growth, bpi.growth)
        @test alias === GrowthRate.Map(alias).growth
        @test alias === GrowthRate(alias).growth
    end

    @bpfails(GrowthRate.Map([:b => :x]), GrowthRate.Map, :construct,
        (d, :x, (:u, [1, :right]), "Expected values of type '$Float64'."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(GrowthRate([:a => -5]), GrowthRate.Map, :construct,
        (d, -5.0, (:u, (:a,)), "Value cannot be negative."))
    @bpfails(GrowthRate([1 => -5]), GrowthRate.Map, :construct,
        (d, -5.0, (:u, (1,)), "Value cannot be negative."))
    # Incomplete should be okay though: sparse within parent class.
    @test GrowthRate([2 => 5]).growth == OrderedDict([2 => 5.0])

    bp.growth[:b] *= -10
    bpi.growth[2] *= -100
    addfails.@check(base + bp, [],
        (GrowthRate.Map, :early, (d, -50.0, (:u, (:b,)), "Value cannot be negative.")))
    addfails.@check(base + bpi, [],
        (GrowthRate.Map, :early, (d, -500.0, (:u, (2,)), "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    pop!(bp.growth, :b)
    addfails.@check(base + bp, [],
        (GrowthRate.Map, :late,
            (d, bp.growth, :mwhole, "Missing: no value provided for :b.")))

    bp = GrowthRate([:c => 7, l...])
    addfails.@check(base + bp, [],
        (GrowthRate.Map, :late,
            (d, bp.growth, :mwhole, "Not a :producer name: :c.")))

    pop!(bpi.growth, 2)
    addfails.@check(base + bpi, [],
        (GrowthRate.Map, :late,
            (d, bpi.growth, :mwhole, "Missing: no value provided for node 2.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp, bpi = GrowthRate(l), GrowthRate(li)
    m = base + bp
    mi = base + bpi
    for m in [m, mi]
        @test has_component(m, GrowthRate)
        @test_disp(m,
            """
            Model (alias for $(F.System){$(N.Network)}) with 3 components:
              - Species: 4 (:a, :b, :c, :d)
              - Foodweb: 3 links, 2 producers, 2 consumers, 2 preys, 2 tops.
              - GrowthRate: [·, 5.0, ·, 8.0]\
            """
        )
    end

    # ======================================================================================
    # From a flat scalar.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = GrowthRate.Flat(5.0)
    @test bp.growth isa Float64
    @test bp == GrowthRate.Flat(5)
    @test bp == GrowthRate.Flat(0x5)
    @test bp == GrowthRate.Flat(5//1)
    @test bp == GrowthRate(5)
    @test bp == GrowthRate(0x5)
    @test bp == GrowthRate(5//1)
    @test GrowthRate.Flat(1.0) == GrowthRate.Flat(true)
    @test GrowthRate.Flat(1.0) == GrowthRate(true)
    @test_repr(bp, "<GrowthRate>:Flat(growth: 5.0)")
    @test_disp(bp,
        """
        blueprint for <GrowthRate>: Flat {
          growth: 5.0,
        }\
        """)

    @bpfails(GrowthRate.Flat(:x), GrowthRate.Flat, :construct,
        (d, :x, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(GrowthRate(-1), GrowthRate.Flat, :construct,
        (d, -1.0, :uwhole, "Value cannot be negative."))

    bp.growth *= -2
    addfails.@check(base + bp, [],
        (GrowthRate.Flat, :early, (d, -10.0, :uwhole, "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = GrowthRate(5)
    m = base + bp
    @test has_component(m, GrowthRate)
    @test_disp(m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 3 links, 2 producers, 2 consumers, 2 preys, 2 tops.
          - GrowthRate: [·, 5.0, ·, 5.0]\
        """)
end

@testset "SubnodeField component: view" begin

    # The values become available as a view.
    m = Model(Foodweb([:a => :b, :c => (:b, :d)]), GrowthRate([5, 8]))
    v = m.producers.growth

    @test v isa View
    @test_repr(v, "<species:producers:growth>[·, 5.0, ·, 8.0]")
    @test_disp(
        v,
        """
        SubnodesFieldView<species:producers:growth>{Float64} (2/4 values)
         ·
         5.0
         ·
         8.0\
        """,
    )

    @propfails(Model().producers.growth, Pr, :growth,
        "Component <GrowthRate> is required to read this property.")

    # The view may be extracted as a regular sparse vector.
    e = extract(v)
    @test e isa SparseVector{Float64}
    @test e == sparse([0, 5, 0, 8])

    # Basic indexing *relative to parent class*:
    # zeroes are created to answer "non-structural" accesses.
    @test v[1] == 0
    @test v[0x2] == 5
    @test v[:c] == 0
    @test v['d'] == 8

    # The view has some basic vector-like interface,
    @test v isa AbstractVector{Float64}
    @test v[end] == 8
    @test v[end-1] == 0
    @test v[(end-1):end] == [0, 8]
    @test v[1:2] == [0, 5]
    @test v[Bool[1, 0, 0, 1]] == [0, 8]
    @test v[[1, 4]] == [0, 8]
    @test v == collect(v) == [0, 5, 0, 8] == [i for i in v]
    @test v[[:a, :d]] == [0, 8]

    # And also sparse-vector-like.
    @test v isa AbstractSparseVector{Float64,Int}
    @test nnz(v) == 2
    nz = nonzeros(v)
    @test nz isa Vector{Float64}
    @test nz == [5, 8]
    sim = similar(v)
    @test sim isa SparseVector{Float64,Int}
    @test sim == spzeros(Float64, 4)
    @test findnz(v) == findnz(e)
    @test v[2:3] isa Vector{Float64} # TODO: have this be sparse? See `Web` view tests.

    @viewfails(v[-5], (d, -5, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[5], (d, 5, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[:x], (d, :x, :uwhole, "No node in this class is labeled :x."))
    @viewfails(v[end+1], (d, 5, :uwhole, "There are 4 nodes in this class."))

    @test_err(v[5],
        """
        Cannot index into <species:producers:growth> with [5]:
        There are 4 nodes in this class.\
        """)

    @test_err(v[], "BoundsError: attempt to access 4-element $View at index []")
    @test_err(v[1, 2], "BoundsError: attempt to access 4-element $View at index [1, 2]")
    @test_err(v[1, 2, 3],
        "BoundsError: attempt to access 4-element $View at index [1, 2, 3]")
    @test_err(v[true], "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(3,)], "ArgumentError: invalid index: (3,) of type Tuple{$Int}")
    @test_err(v[0x8000000000000000], "InexactError: convert(Int64, 0x8000000000000000)")
    @test_err(v[(end-1):(end+1)],
        "BoundsError: attempt to access 4-element $View at index [3:5]")
    @test_err(v[Bool[0, 1]],
        "BoundsError: attempt to access 4-element $View at index [2-element Vector{Bool}]")

end

@testset "SubnodeField component: mutate" begin

    m = Model(Foodweb([:a => :b, :c => (:b, :d)]), GrowthRate([5, 8]))
    v = m.producers.growth

    # Check COW behaviour.
    w = m.producers.growth
    alt = copy(m)
    a = alt.producers.growth
    @test a == w == [0, 5, 0, 8]

    v[2] *= 10
    v[:d] *= 2
    @test v == w == m.producers.growth == [0, 50, 0, 16]
    @test a == alt.producers.growth == [0, 5, 0, 8]

    # Guard against de-nulling non-structural values.
    @mutfails(v[1] += 1, (d, 1.0, (:m, ((1, :a),)), "Not a null value for a non-producer."))
    @mutfails(
        v[:c] += 2,
        (d, 2.0, (:m, ((3, :c),)), "Not a null value for a non-producer.")
    )

    # Use whole property to reassign.
    input = [0, 4, 0, 6]
    m.producers.growth = input
    @test v == w == m.producers.growth == [0, 4, 0, 6]
    @test a == alt.producers.growth == [0, 5, 0, 8]
    input[2] *= 10
    @test input == [0, 40, 0, 6]
    @test v == w == m.producers.growth == [0, 4, 0, 6] # Not aliasing reassignment.

    # ======================================================================================
    # ↑ ↑ ↑ HERE upgrade tests ↑ ↑ ↑
    # ======================================================================================

    error("STOP HERE")

    # The field is mutable, but only for structural values, unless it would result in zero.
    w = m.growth_rate
    alt = copy(m)
    a = alt.growth_rate
    @test a == w == [0, 5, 0, 8]
    v[2] *= 10
    v[:d] += 100
    v[1] = 0 # (zero is okay)
    v[:a] *= 50 # (still zero)
    @test v == w == m.growth_rate == [0, 50, 0, 108]
    @test a == alt.growth_rate == [0, 5, 0, 8]

    # Support various mutating operations like regular julia arrays.
    v[2:2] .= 15
    v[(end-1):end] .*= 16
    @test v == w == m.growth_rate == [0, 15, 0, 1728]
    @test a == alt.growth_rate == [0, 5, 0, 8]

    v .= [0, 7, 0, 9]
    @test v == w == m.growth_rate == [0, 7, 0, 9]
    @test a == alt.growth_rate == [0, 5, 0, 8]

    # Guard against writing nonzeros in non-structural slots.
    @viewfails(
        v[:a] = 2,
        View,
        "Species [:a] is not a producer so it has no :growth to mutate."
    )
    for invalid in [() -> v[1] = 2, () -> v[1:2] .= 2, () -> v[1:2] .+= 1]
        @viewfails(
            invalid(),
            View,
            "Species [1] is not a producer so it has no :growth to mutate."
        )
    end

    # Guard structural values.
    @mutfails(
        v[2] = -1, # /!\ Error yields local index.
        "When attempting to mutate <species:producers:growth> node field:\n\
         At node with label :b ([1]):\n\
         Value cannot be negative.\n\
         Received: -1.0"
    )
    @mutfails(
        v[:b] = -10,
        "When attempting to mutate <species:producers:growth> node field:\n\
         At node with label :b ([1]):\n\
         Value cannot be negative.\n\
         Received: -10.0"
    )
    @mutfails(
        v[2:2] .-= 10, # /!\ Error yields local index again.
        "When attempting to mutate <species:producers:growth> node field:\n\
         At node with label :b ([1]):\n\
         Value cannot be negative.\n\
         Received: -3.0"
    )

    # And all regular index guards are set.
    @viewfails(
        v[nothing] = 1,
        View,
        "Views are indexed with indices (::Int) or labels (::Symbol). \
         Cannot index with: nothing ::Nothing."
    )
    @viewfails(v[0] = 1, View, "Cannot index with [0] into a class with 4 :species nodes.")
    @viewfails(v[5] = 1, View, "Cannot index with [5] into a class with 4 :species nodes.")
    @viewfails(
        v[:x] = 1,
        View,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c, :d]."
    )
    @viewfails(v[] = 1, View, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2] = 1, View, "Cannot index into nodes with 2 dimensions: [1, 2].")
    for invalid_set in [() -> v[1:2] = 8, () -> v[(end-1):end] *= 10]
        @viewfails(
            invalid_set(),
            View,
            "Indexed assignment with a single value to possibly many locations \
             is not supported; perhaps use broadcasting `.=` instead?"
        )
    end

    # The field can also be pseudo-'reassigned', although this leaks no reference.
    m.growth_rate = [6, 4]
    @test m.growth_rate == v == [0, 6, 0, 4]

    # Reassignnment also works with mapped input.
    m.growth_rate = Dict(:b => 2, :d => 7)
    @test m.growth_rate == v == [0, 2, 0, 7]

    # It may be partial/incomplete in this case.
    m.growth_rate = Dict(:d => 777)
    @test m.growth_rate == v == [0, 2, 0, 777]

    # Or anything that could be used as a typical blueprint constructor.
    m.growth_rate = 5
    @test m.growth_rate == v == [0, 5, 0, 5]

    # Checked.
    @bpfails(
        m.growth_rate = [6, -1],
        "When attempting to assign to <species:producers:growth> node field:\n\
         At node index [2]:\n\
         Value cannot be negative.",
        -1,
    )
    @bpfails(
        m.growth_rate = Dict(:c => 2),
        "When attempting to assign to <species:producers:growth> node field:\n\
         Not a :producers name: :c.",
    )
    @bpfails(
        m.growth_rate = -1,
        "When attempting to assign to <species:producers:growth> node field:\n\
         Value cannot be negative.",
        -1,
    )
    @bpfails(
        m.growth_rate = :what,
        "When attempting to assign to <species:producers:growth> node field:\n\
         Cannot convert input to either:\n  \
          - $Float64\n  \
          - $Vector{$Float64}\n  \
          - $OrderedDict{R, $Float64} where R",
        :what,
    )

    # Fail constructing from raw values.
    input = [5, -8]
    for invalid in (() -> GrowthRate.Raw(input), () -> GrowthRate(input))
        @bpfails(
            invalid(),
            "When constructing <species:producers:growth> from raw values:\n\
             At node index [2]:\n\
             Value cannot be negative.",
            -8,
        )
    end

    # Alias to the value inside the blueprint if exact type match.
    input = Float64[5, 8]
    bp = GrowthRate(input)
    @test bp.growth === input
    input[2] *= 10
    @test bp.growth == [5, 80]

    # It is (still) ok to break values checking afterwards..
    input[2] *= -1
    # .. but then expansion fails.
    addfails.@check(
        base + bp,
        Check(
            early,
            [GrowthRate.Raw],
            "When checking <species:producers:growth> blueprint data:\n\
             At node index [2]:\n\
             Value cannot be negative.\n\
             Received: -80.0",
        )
    )

    # Construct from mapped values.
    map = [:b => 3, :d => 6]
    bp = GrowthRate.Map(map)
    @test bp == GrowthRate(map) # Directly dispatched from component.
    @test is_repr(bp, "<GrowthRate>:Map(growth: {b: 3.0, d: 6.0})")
    @test is_disp(
        bp,
        """
        blueprint for <GrowthRate>: Map {\n  \
          growth: {b: 3.0, d: 6.0},\n\
        }\
        """,
    )
    m = base + bp
    @test m.growth_rate == [0, 3, 0, 6]

    # Late-check against node names.
    addfails.@check(
        base + GrowthRate([:a => 5, :b => 6]),
        Check(
            late,
            [GrowthRate.Map],
            "When checking <species:producers:growth> blueprint against model:\n\
             Missing for <species:producers:growth>, no value provided for :d.",
        )
    )
    addfails.@check(
        base + GrowthRate([:b => 5, :d => 6, :x => 8, :y => 9]),
        Check(
            late,
            [GrowthRate.Map],
            "When checking <species:producers:growth> blueprint against model:\n\
             Not :producers names: :x and :y.",
        )
    )

    # Indices within the map are expected to reference within the *parent* class.
    imap = [2 => 8, 4 => 1]
    bp = GrowthRate.Map(imap)
    @test bp == GrowthRate(imap)
    @test is_repr(bp, "<GrowthRate>:Map(growth: {2: 8.0, 4: 1.0})")
    @test is_disp(
        bp,
        """
        blueprint for <GrowthRate>: Map {\n  \
          growth: {2: 8.0, 4: 1.0},\n\
        }\
        """,
    )
    m = base + bp
    @test m.growth_rate == [0, 8, 0, 1]

    addfails.@check(
        base + GrowthRate([2 => 5]),
        Check(
            late,
            [GrowthRate.Map],
            "Missing for <species:producers:growth>, \
             no value provided for :species node 4.",
        )
    )
    addfails.@check(
        base + GrowthRate([2 => 5, 4 => 8, 3 => 7]),
        Check(late, [GrowthRate.Map], "Invalid index for producers within species: 3.")
    )

    # Alias blueprint if exact input is used.
    input = bp.growth
    bp = GrowthRate(input)
    @test bp.growth === input
    input[2] *= 10
    @test bp.growth == OrderedDict([2 => 80, 4 => 1])
    input[4] *= -1
    addfails.@check(
        base + bp,
        Check(
            early,
            [GrowthRate.Map],
            "When checking <species:producers:growth> blueprint data:\n\
             At node index [4]:\n\
             Value cannot be negative.\n\
             Received: -1.0",
        )
    )

    # Fail constructing from mapped.
    @bpfails(
        GrowthRate.Map([:a => :what]),
        "When constructing <species:producers:growth> from map:\n\
         Expected values of type '$Float64', \
         received instead at [1][right]: :what ::Symbol.",
    )

    # Construct from a flat value.
    bp = GrowthRate.Flat(3)
    @test bp == GrowthRate(3)
    m = base + bp
    @test m.growth_rate == [0, 3, 0, 3]
    bp.growth *= -1 # Mutable.
    addfails.@check(
        base + bp,
        Check(
            early,
            [GrowthRate.Flat],
            "When checking <species:producers:growth> blueprint data:\n\
             Value cannot be negative.\n\
             Received: -3.0",
        )
    )

    # Fail constructing from Flat.
    @bpfails(
        GrowthRate.Flat(:what),
        "When constructing <species:producers:growth> from a flat value",
        :what,
        Float64,
        "Conversion not implemented.",
    )

    # Generic construction failure.
    @bpfails(
        GrowthRate('w'),
        "Cannot convert input to either:\n  \
          - $Float64\n  \
          - $(Vector{Float64})\n  \
          - $(Map{Float64})",
        'w',
    )

end

# HERE: feature a `SubnodeField.Sparse` blueprint, that would match the parent size.
# Also feature a `model.field.dense` view, with the usual rules.

end

"""
Test all aspects of typical SubnodeField component, using producer growth as an example.
"""
module SubnodeFieldTest

using EcologicalNetworksDynamics
using SparseArrays

using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, N, F, Views, SubnodeField, Map
import Main:
    is_disp, is_repr, @argfails, @writefails, @inputfails, @viewfails, @sysfails, Value
const View = # Tested viewtype.
    Views.SubnodesFieldView{SubnodeField(:producers, :growth, :species),Float64}

@testset "Typical SubnodeField component" begin

    @test GrowthRate isa EN.Component
    @test is_repr(GrowthRate, "GrowthRate")
    @test is_disp(
        GrowthRate,
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
    @test GrowthRate.Raw <: EN.Blueprint
    @test GrowthRate.Map <: EN.Blueprint
    @test GrowthRate.Flat <: EN.Blueprint

    # Growth rate is only defined / can only be set for producers.
    base = Model(Foodweb([:a => :b, :c => (:b, :d)]))
    @test base.producers.mask == [0, 1, 0, 1]

    # Careful: 'Raw' means 1 value per node in the subclass, not the parent.
    bp = GrowthRate.Raw([5, 8])
    @test bp == GrowthRate([5, 8])

    # Expand.
    m = base + bp
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 3 links, 2 producers, 2 consumers, 2 preys, 2 tops.
          - GrowthRate: [·, 5.0, ·, 8.0].\
        """,
    )
    @sysfails(Model(bp), Missing(Foodweb, GrowthRate, [GrowthRate.Raw], nothing))

    # The values become available as a view.
    v = m.growth_rate
    @test v isa View
    @test v isa AbstractVector{Float64}
    @test v isa AbstractSparseVector{Float64,Int}
    @test is_repr(v, "<species:producers:growth>[·, 5.0, ·, 8.0]")
    @test is_disp(
        v,
        """
        SubnodesFieldView<species:producers:growth>{Float64} (2/4 values)
         ·
         5.0
         ·
         8.0\
        """,
    )
    @sysfails( # Unless the component is missing, as all properties.
        Model().growth_rate,
        Property(
            growth_rate,
            "Component $(EN._GrowthRate) is required to read this property.",
        ),
    )

    # The view has some basic sparse-vector-like interface,
    @test v == collect(v) == [0, 5, 0, 8] == [r for r in v]

    # The view may be extracted as a regular sparse vector.
    e = extract(v)
    @test e isa SparseVector{Float64}
    @test e == v == sparse([0, 5, 0, 8])

    # Zeroes are created to answer "non-structural" accesses.
    @test v[1] == 0
    @test v[2] == 5
    @test v[:c] == 0
    @test v[:d] == 8
    @test v[end] == 8
    @test v[end-1:end] == [0, 8]
    @viewfails(
        v[nothing],
        View,
        "Views are indexed with indices (::Int) or labels (::Symbol). \
         Cannot index with: nothing ::Nothing."
    )
    @viewfails(v[0], View, "Cannot index with [0] into a class with 4 :species nodes.")
    @viewfails(v[5], View, "Cannot index with [5] into a class with 4 :species nodes.")
    @viewfails(
        v[:x],
        View,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c, :d]."
    )
    @viewfails(v[], View, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2], View, "Cannot index into nodes with 2 dimensions: [1, 2].")

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
    v[end-1:end] .*= 16
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
    @writefails(
        v[2] = -1,
        growth[1] = -1, # /!\ Error yields local index.
        "When attempting to mutate <species:producers:growth> node field:\n\
         At node with label :b ([1]):\n\
         Value cannot be negative.\n\
         Received: -1.0"
    )
    @writefails(
        v[:b] = -10,
        growth[:b] = -10,
        "When attempting to mutate <species:producers:growth> node field:\n\
         At node with label :b ([1]):\n\
         Value cannot be negative.\n\
         Received: -10.0"
    )
    @writefails(
        v[2:2] .-= 10,
        growth[1] = -3, # /!\ Error yields local index again.
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
    for invalid_set in [() -> v[1:2] = 8, () -> v[end-1:end] *= 10]
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
    @inputfails(
        m.growth_rate = [6, -1],
        "When attempting to assign to <species:producers:growth> node field:\n\
         At node index [2]:\n\
         Value cannot be negative.",
        -1,
    )
    @inputfails(
        m.growth_rate = Dict(:c => 2),
        "When attempting to assign to <species:producers:growth> node field:\n\
         Not a :producers name: :c.",
    )
    @inputfails(
        m.growth_rate = -1,
        "When attempting to assign to <species:producers:growth> node field:\n\
         Value cannot be negative.",
        -1,
    )
    @inputfails(
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
        @inputfails(
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
    @sysfails(
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
    @sysfails(
        base + GrowthRate([:a => 5, :b => 6]),
        Check(
            late,
            [GrowthRate.Map],
            "When checking <species:producers:growth> blueprint against model:\n\
             Missing for <species:producers:growth>, no value provided for :d.",
        )
    )
    @sysfails(
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

    @sysfails(
        base + GrowthRate([2 => 5]),
        Check(
            late,
            [GrowthRate.Map],
            "Missing for <species:producers:growth>, \
             no value provided for :species node 4.",
        )
    )
    @sysfails(
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
    @sysfails(
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
    @inputfails(
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
    @sysfails(
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
    @inputfails(
        GrowthRate.Flat(:what),
        "When constructing <species:producers:growth> from a flat value",
        :what,
        Float64,
        "Conversion not implemented.",
    )

    # Generic construction failure.
    @inputfails(
        GrowthRate('w'),
        "Cannot convert input to either:\n  \
          - $Float64\n  \
          - $(Vector{Float64})\n  \
          - $(Map{Float64})",
        'w',
    )

end

end

"Test all aspects of typical NodeField component, using body mass as an example."
module NodeFieldTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.NetworkFramework: EN, N, F, NF, D, V
using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @jl_basic_callfails, @checkfails, addfails, @bpfails,
    @propfails, @viewfails, @mutfails
using OrderedCollections
using SparseArrays
using Test

const d, _D = D.NodeField(:species, :body_mass)
const View = V.NodeFieldView{d,Float64}

@testset "NodeField component: blueprints" begin

    @test BodyMass isa Component # Etc.
    @test BodyMass.Z <: Blueprint # Extension point for extra BP worked, but test Z later.

    # ======================================================================================
    # From raw values.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = BodyMass.Raw([4.0, 5.0, 6.0])
    @test bp.M isa Vector{Float64}
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
        BodyMass.Raw, :construct, (d, :x, (3,), nothing,
        "Cannot convert to `$Float64`:\n\
         Conversion not implemented."))
    @checkfails(BodyMass(invalid), d, invalid, :whole, nothing,
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
        BodyMass.Raw, :construct, (d, -5.0, (2,), nothing, "Value cannot be negative."))

    #---------------------------------------------------------------------------------------
    # Early check.

    alias[3] *= -1
    addfails.@check(Model(bp), [],
        (BodyMass.Raw, :early, (d, -6.0, (3,), nothing, "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("abc"), BodyMass([1, 2])), [],
        (BodyMass.Raw, :late,
            (d, [1.0, 2.0], :whole, :whole,
                "Wrong number of values received: expected 3, got 2.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = BodyMass([4, 5, 6])
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

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = BodyMass.Map(l)
    bpi = BodyMass.Map(li)
    @test bp.M isa OrderedDict{Symbol,Float64}
    @test bpi.M isa OrderedDict{Int,Float64}
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
        (d, [5, 8], [1, :right], nothing, "Expected values of type 'Float64'."))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(BodyMass([:a => -5]), BodyMass.Map, :construct,
        (d, -5.0, (:a,), nothing, "Value cannot be negative."))
    @bpfails(BodyMass([1 => -5]), BodyMass.Map, :construct,
        (d, -5.0, (1,), nothing, "Value cannot be negative."))
    @bpfails(BodyMass([2 => 5]), BodyMass.Map, :construct,
        (d, 2, (2,), nothing,
            "There is only 1 value in the given map so no index can be 2."))

    #---------------------------------------------------------------------------------------
    # Early check.

    bp.M[:b] *= -1
    bpi.M[2] *= -1
    addfails.@check(Model(bp), [],
        (BodyMass.Map, :early, (d, -5.0, (:b,), nothing, "Value cannot be negative.")))
    addfails.@check(Model(bpi), [],
        (BodyMass.Map, :early, (d, -5.0, (2,), nothing, "Value cannot be negative.")))
    pop!(bpi.M, 2)
    addfails.@check(Model(bpi), [],
        (BodyMass.Map, :early,
            (d, 3, (3,), nothing,
                "There are only 2 values in the given map so no index can be 3.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("abc"), BodyMass([:a => 1])), [],
        (BodyMass.Map, :late,
            (d, OrderedDict([:a => 1.0]), :whole, :whole,
                "Missing: no value provided for :b and :c.")))
    addfails.@check(Model(Species("a"), BodyMass([:a => 1, :x => 2])), [],
        (BodyMass.Map, :late,
            (d, OrderedDict([:a => 1.0, :x => 2.0]), :whole, :whole,
                "Not a :species name: :x.")))

    # (inconsistent indices map cannot even get through early check)

    #---------------------------------------------------------------------------------------
    # Expand.

    bp, bpi = BodyMass(l), BodyMass(li)
    m = Model(bp)
    mi = Model(bpi)
    @test has_component(m, BodyMass)
    @test has_component(mi, BodyMass)
    # Implied.
    @test has_component(m, Species)
    @test has_component(mi, Species)
    @test m.species.names == [:a, :b, :c]
    @test mi.species.names == [:s1, :s2, :s3]
    @test_disp(m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 2 components:
          - Species: 3 (:a, :b, :c)
          - BodyMass: [4.0, 5.0, 6.0]\
        """)
    @test_disp(mi,
        """
        Model (alias for $(F.System){$(N.Network)}) with 2 components:
          - Species: 3 (:s1, :s2, :s3)
          - BodyMass: [4.0, 5.0, 6.0]\
        """)

    # ======================================================================================
    # From a flat scalar.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = BodyMass.Flat(5.0)
    @test bp.M isa Float64
    @test bp == BodyMass.Flat(5)
    @test bp == BodyMass.Flat(0x5)
    @test bp == BodyMass.Flat(5//1)
    @test bp == BodyMass(5)
    @test bp == BodyMass(0x5)
    @test bp == BodyMass(5//1)
    @test BodyMass.Flat(1.0) == BodyMass.Flat(true)
    @test BodyMass(1.0) == BodyMass(true)
    @test_repr(bp, "<BodyMass>:Flat(M: 5.0)")
    @test_disp(
        bp,
        """
        blueprint for <BodyMass>: Flat {
          M: 5.0,
        }\
        """
    )

    @bpfails(BodyMass.Flat(:a), BodyMass.Flat, :construct,
        (d, :a, :whole, nothing,
            "Cannot convert to `$Float64`:\n\
             Conversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(BodyMass(-5), BodyMass.Flat, :construct,
        (d, -5.0, :whole, nothing, "Value cannot be negative."))

    #---------------------------------------------------------------------------------------
    # Early check.

    m = Model(Species("abc"))

    bp.M *= -1
    addfails.@check(m + bp, [],
        (BodyMass.Flat, :early,
            (d, -5.0, :whole, nothing, "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = BodyMass(5)
    m += bp
    @test has_component(m, BodyMass)
    @test_disp(m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 2 components:
          - Species: 3 (:a, :b, :c)
          - BodyMass: [5.0, 5.0, 5.0]\
        """)
end

@testset "NodeField component: view (read)" begin

    m = Model(Species("abc"), BodyMass([4, 5, 6]))
    v = m.body_mass
    @test v isa View
    @test v isa AbstractVector{Float64}
    @test v == collect(v) == [4, 5, 6] == [i for i in v]

    @test_repr(v, "<species:body_mass>[4.0, 5.0, 6.0]")
    @test_disp(v,
        """
        NodeFieldView<species:body_mass>{Float64} (3 values)
         4.0
         5.0
         6.0\
        """)

    @propfails(Model().body_mass, Model, :body_mass,
        "Component <BodyMass> is required to read this property.")

    e = extract(v)
    @test e isa Vector{Float64}
    @test e == v

    @test v[1] == 4
    @test v[0x2] == 5
    @test v[:c] == 6
    @test v['a'] == 4
    @test v["b"] == 5
    @test v[split("c")...] == 6

    @test v[end] == 6
    @test v[end-1] == 5
    @test v[1:2] == [4, 5]
    @test v[(end-1):end] == [5, 6]
    @test v[[true, false, true]] == v[[1, 0, 1]] == [4, 6]

    @viewfails(v[],
        (d, (), :whole, nothing, "Node-level data has 1 dimension, received 0."))
    @viewfails(v[1, 2],
        (d, (1, 2), :whole, nothing, "Node-level data has 1 dimension, received 2."))
    @viewfails(v[1, 2, 3],
        (d, (1, 2, 3), :whole, nothing, "Node-level data has 1 dimension, received 3."))
    @viewfails(v[true],
        (d, true, (1,), nothing,
            "Views are queried with indices [::Int] or labels [::Symbol], not `$Bool`."))
    @viewfails(v[(3,)],
        (d, (3,), (1,), nothing, "Cannot index into views with explicit tuples."))
    @viewfails(v[0x8000000000000000],
        (d, 0x8000000000000000, (1,), nothing,
            "Index too large to be used with julia arrays (9223372036854775808)."))
    @viewfails(v[-5],
        (d, -5, (1,), nothing, "Integer node references can only be positive."))
    @viewfails(v[[0, 1, 2]],
        (d, 2, (1, (3,)), nothing,
            "Could not interpret as a boolean mask:\n\
             Cannot convert to `$(SparseVector{Bool, Int})`:\n\
             (detail down the stacktrace)"))
    @viewfails(v[5], (d, 5, (1,), nothing, "This class only contains 3 nodes."))
    @viewfails(v[:x], (d, :x, (1,), nothing, "No node in this class is labeled :x."))
    @viewfails(v[end+1], (d, 4, (1,), nothing, "This class only contains 3 nodes."))
    @viewfails(v[(end-1):(end+1)],
        (d, 4, (1, (:last,)), nothing, "This class only contains 3 nodes."))
    @viewfails(v[[0, 1]],
        (d, sparse(Bool[0, 1]), (1,), nothing,
            "The given mask is of size 2 but there are 3 nodes in the class."))
    @viewfails(Model(BodyMass([5])).body_mass[[0, 1]],
        (d, sparse(Bool[0, 1]), (1,), nothing,
            "The given mask is of size 2 but there is 1 node in the class."))

end

@testset "NodeField component: mutate" begin

    m = Model(Species("abc"), BodyMass([4, 5, 6]))
    v = m.body_mass

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

    # Alternately use whole property to reassign.
    m.body_mass = [9, 5, 1]
    @test v == w == m.body_mass == [9, 5, 1]

    # Sophisticated reassign: map-like.
    m.body_mass = (; a = 7, c = 3)
    @test v == w == m.body_mass == [7, 5, 3]
    m.body_mass = [3 => 8, 1 => 9]
    @test v == w == m.body_mass == [9, 5, 8]

    # Or flat-like.
    m.body_mass = 2
    @test v == w == m.body_mass == [2, 2, 2]

    # AbstractArray also provides more sophisticated indexed mutation options.
    v[2:3] = [3, 4] # Ranges.
    @test v == w == m.body_mass == [2, 3, 4]
    v[v .!= 3] = [8, 9] # Masks.
    @test v == w == m.body_mass == [8, 3, 9]
    v[2:3] .= 7 # Broadcast.
    @test v == w == m.body_mass == [8, 7, 7]
    v[[2, 3, 1]] = [3, 5, 7] # Indices vector.
    @test v == w == m.body_mass == [7, 3, 5]
    # One extension: accept labels vector.
    v[[:a, :c]] = [8, 9]
    @test v == w == m.body_mass == [8, 3, 9]

    # Still unchanged.
    @test a == alt.body_mass == [4, 5, 6]

    error("STOP HERE")
    # ======================================================================================
    # ↑ ↑ ↑ HERE update tests ↑ ↑ ↑
    # ======================================================================================

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

"Test all aspects of typical NodeField component, using body mass as an example."
module NodeFieldTest

# Much inspired by `ClassTest`.

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.NetworkFramework: EN, N, F, NF, D, V
using EcologicalNetworksDynamics.Tests:
    @test_err, @test_repr, @test_disp, @jl_basic_callfails, @checkfails, addfails, @bpfails,
    @propfails, @viewfails, @mutfails, @viewfails, @argfails, @netfails
using OrderedCollections
using SparseArrays
using Test

const d, _D = D.NodeField(:species, :body_mass)
const View = V.NodeFieldView{d,Float64}

@testset "NodeField components: blueprints" begin

    @test BodyMass isa Component
    @test BodyMass.Z <: Blueprint # Extension point for extra BP worked, but test Z later.
    @test_disp(BodyMass,
        """
        BodyMass (component for $(N.Network), expandable from:
          Raw: raw values,
          Map: [species => body_mass] map,
          Flat: uniform value,
          Z: trophic levels,
        )\
        """)

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
    @test_disp(bp,
        """
        blueprint for <BodyMass>: Raw {
          M: [4.0, 5.0, 6.0],
        }\
        """)

    alias = bp.M
    @test alias === BodyMass.Raw(alias).M
    @test alias === BodyMass(alias).M

    invalid = [4, 5, :x]
    @bpfails(BodyMass.Raw(invalid),
        BodyMass.Raw, :construct, (d, :x, (:u, (3,)),
        "Cannot convert to `$Float64`:\n\
         Conversion not implemented."))
    @checkfails(BodyMass(invalid), d, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(NF.Map{Float64})
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(BodyMass([4, -5, 6]),
        BodyMass.Raw, :construct, (d, -5.0, (:u, (2,)), "Value cannot be negative."))

    alias[3] *= -1
    addfails.@check(Model(bp), [],
        (BodyMass.Raw, :early, (d, -6.0, (:u, (3,)), "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("abc"), BodyMass([1, 2])), [],
        (BodyMass.Raw, :late,
            (d, [1.0, 2.0], :mwhole,
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
        Model (alias for $Model) with 2 components:
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
        @test alias === BodyMass.Map(alias).M
        @test alias === BodyMass(alias).M
    end

    @bpfails(BodyMass.Map([:a => [5, 8]]), BodyMass.Map, :construct,
        (d, [5, 8], (:u, [1, :right]), "Expected values of type '$Float64'."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(BodyMass([:a => -5]), BodyMass.Map, :construct,
        (d, -5.0, (:u, (:a,)), "Value cannot be negative."))
    @bpfails(BodyMass([1 => -5]), BodyMass.Map, :construct,
        (d, -5.0, (:u, (1,)), "Value cannot be negative."))
    @bpfails(BodyMass([2 => 5]), BodyMass.Map, :construct,
        (d, 2, (:u, (2,)), "There is only 1 value in the given map so no index can be 2."))

    bp.M[:b] *= -1
    bpi.M[2] *= -1
    addfails.@check(Model(bp), [],
        (BodyMass.Map, :early, (d, -5.0, (:u, (:b,)), "Value cannot be negative.")))
    addfails.@check(Model(bpi), [],
        (BodyMass.Map, :early, (d, -5.0, (:u, (2,)), "Value cannot be negative.")))
    pop!(bpi.M, 2)
    addfails.@check(Model(bpi), [],
        (BodyMass.Map, :early,
            (d, 3, (:u, (3,)),
                "There are only 2 values in the given map so no index can be 3.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("abc"), BodyMass([:a => 1])), [],
        (BodyMass.Map, :late,
            (d, OrderedDict([:a => 1.0]), :mwhole,
                "Missing: no value provided for :b and :c.")))
    addfails.@check(Model(Species("a"), BodyMass([:a => 1, :x => 2])), [],
        (BodyMass.Map, :late,
            (d, OrderedDict([:a => 1.0, :x => 2.0]), :mwhole, "Not a species name: :x.")))
    addfails.@check(Model(Species(3), BodyMass([1 => 5])), [],
        (BodyMass.Map, :late,
            (d, OrderedDict([1 => 5.0]), :mwhole,
                "Missing: no value provided for nodes 2 and 3.")))

    # (inconsistent indices map cannot even get through early check)

    # NOTE: Late checking of *values* is also performed,
    # but irrelevant for body_mass so not tested here.
    # Instead, they are tested at metabolic_class.

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
        Model (alias for $Model) with 2 components:
          - Species: 3 (:a, :b, :c)
          - BodyMass: [4.0, 5.0, 6.0]\
        """)
    @test_disp(mi,
        """
        Model (alias for $Model) with 2 components:
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
        (d, :a, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(BodyMass(-5), BodyMass.Flat, :construct,
        (d, -5.0, :uwhole, "Value cannot be negative."))

    m = Model(Species("abc"))

    bp.M *= -1
    addfails.@check(m + bp, [],
        (BodyMass.Flat, :early, (d, -5.0, :uwhole, "Value cannot be negative.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = BodyMass(5)
    m += bp
    @test has_component(m, BodyMass)
    @test_disp(m,
        """
        Model (alias for $Model) with 2 components:
          - Species: 3 (:a, :b, :c)
          - BodyMass: [5.0, 5.0, 5.0]\
        """)

    # Species are required then.
    addfails.@missing(Model(bp), Species, BodyMass, [BodyMass.Flat], nothing)
end

@testset "NodeField components: view" begin

    m = Model(Species("abc"), BodyMass([4, 5, 6]))
    v = m.body_mass
    @test v isa View

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
    @test e == v == [4, 5, 6]

    # Basic indexing.
    @test v[1] == 4
    @test v[0x2] == 5
    @test v[:c] == 6
    @test v['a'] == 4
    @test v["b"] == 5
    @test v[split("c")...] == 6

    @test v isa AbstractVector{Float64}
    @test v[end] == 6
    @test v[end-1] == 5
    @test v[1:2] == [4, 5]
    @test v[(end-1):end] == [5, 6]
    @test v[Bool[1, 0, 1]] == [4, 6]
    @test v == collect(v) == [4, 5, 6] == [i for i in v]
    @test v[[:a, :c]] == [4, 6]

    @viewfails(v[-5], (d, -5, :uwhole, "There are 3 nodes in this class."))
    @viewfails(v[5], (d, 5, :uwhole, "There are 3 nodes in this class."))
    @viewfails(v[:x], (d, :x, :uwhole, "No node in this class is labeled :x."))
    @viewfails(v[end+1], (d, 4, :uwhole, "There are 3 nodes in this class."))

    @test_err(v[5],
        """
        Cannot index into <species:body_mass> with [5]:
        There are 3 nodes in this class.\
        """)

    @test_err(v[], "BoundsError: attempt to access 3-element $View at index []")
    @test_err(v[1, 2], "BoundsError: attempt to access 3-element $View at index [1, 2]")
    @test_err(v[1, 2, 3],
        "BoundsError: attempt to access 3-element $View at index [1, 2, 3]")
    @test_err(v[true], "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(3,)], "ArgumentError: invalid index: (3,) of type Tuple{$Int}")
    @test_err(v[0x8000000000000000], "InexactError: convert(Int64, 0x8000000000000000)")
    @test_err(v[(end-1):(end+1)],
        "BoundsError: attempt to access 3-element $View at index [2:4]")
    @test_err(v[Bool[0, 1]],
        "BoundsError: attempt to access 3-element $View at index [2-element Vector{Bool}]")

end

@testset "NodeField components: mutate" begin

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
    input = [9, 5, 1]
    m.body_mass = input
    @test v == w == m.body_mass == [9, 5, 1]
    # This importantly leaks no reference within the model, so it's *not* actual reassign.
    input[1] *= 10
    @test input == [90, 5, 1]
    @test v == w == m.body_mass == [9, 5, 1] # Unchanged.

    # Sophisticated reassign: map-like.
    m.body_mass = (; a = 7, c = 3) # (may be partial then)
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
    v .= [1, 2, 3] # Broadcast to it all.
    @test v == w == m.body_mass == [1, 2, 3]
    v[[2, 3, 1]] = [3, 5, 7] # Indices vector.
    @test v == w == m.body_mass == [7, 3, 5]

    # One extension: accept labels vector.
    v[[:a, :c]] = [8, 9]
    @test v == w == m.body_mass == [8, 3, 9]

    # Still unchanged.
    @test a == alt.body_mass == [4, 5, 6]

    # Index-checking is also enabled via `setindex!`.
    @viewfails(v[-5] = 8, (d, -5, :uwhole, "There are 3 nodes in this class."))
    @viewfails(v[5] = 8, (d, 5, :uwhole, "There are 3 nodes in this class."))
    @viewfails(v[end+1] = 8, (d, 4, :uwhole, "There are 3 nodes in this class."))
    @viewfails(v[:x] = 8, (d, :x, :uwhole, "No node in this class is labeled :x."))

    @test_err(v[:x] = 8,
        """
        Cannot index into <species:body_mass> with [:x]:
        No node in this class is labeled :x.\
        """)

    @test_err(v[['a', 'x']] = 8,
        """
        Cannot index into <species:body_mass> with [['a', 'x']]:
        In element [2] within the index:
        No node in this class is labeled :x.
        Received: 'x'  ::Char\
        """)

    @test_err(v[] = 8, "BoundsError: attempt to access 3-element $View at index []")
    @test_err(v[1, 2] = 8, "BoundsError: attempt to access 3-element $View at index [1, 2]")
    @test_err(v[1, 2, 3] = 8,
        "BoundsError: attempt to access 3-element $View at index [1, 2, 3]")
    @test_err(v[true] = 8, "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(3,)] = 8, "ArgumentError: invalid index: (3,) of type Tuple{$Int}")
    @test_err(v[0x8000000000000000] = 8, "InexactError: convert($Int, 0x8000000000000000)")
    @test_err(v[(end-1):(end+1)] = 8,
        "BoundsError: attempt to access 3-element $View at index [2:4]")
    @test_err(v[Bool[0, 1]] = 8,
        "BoundsError: attempt to access 3-element $View at index [2-element Vector{Bool}]")

    # Still unchanged (after failures).
    @test v == w == m.body_mass == [8, 3, 9]
    @test a == alt.body_mass == [4, 5, 6]

    # The value is still checked.
    @mutfails(v .= -5, (d, -5.0, (:m, ((1, :a),)), "Value cannot be negative."))
    @mutfails(v[:a] = -5, (d, -5.0, (:m, ((1, :a),)), "Value cannot be negative."))
    @mutfails(v[2:3] = [1, -5], (d, -5.0, (:m, ((3, :c),)), "Value cannot be negative."))

    # On assignment.
    @mutfails(m.body_mass = [1, 5],
        (d, [1.0, 5.0], :mwhole, "Wrong number of values received: expected 3, got 2."))
    input = [:x => 1.0, :y => 2.0]
    @mutfails(m.body_mass = input,
        (d, OrderedDict(input), :mwhole, "Not species names: :x and :y."))
    @mutfails(m.body_mass = [:a => 1, :c => -2],
        (d, -2.0, (:u, (:c,)), "Value cannot be negative."))

    @test_err(v[2:3] = [1, -5],
        """
        While mutating model:
        In the provided input targetting node value [3] (:c) for <species:body_mass>:
        Value cannot be negative.
        Received: -5.0  ::$Float64\
        """)

    # Although /!\ CAREFUL partial mutation may have been applied.
    #                                 *v*
    @test v == w == m.body_mass == [8, 1, 9]
    @test a == alt.body_mass == [4, 5, 6]

end

@testset "NodeField components: sparse extract" begin

    # Obtain legacy sparse data from view into subnodes field.
    m = Model(Foodweb([:a => :b, :c => (:b, :d)]), GrowthRate([5, 8]), BodyMass(2))

    @test m.producers.growth == [5, 8] # Dense.

    # Dense extract.
    e = extract(m.producers.growth)
    @test e isa Vector{Float64}
    @test e == [5, 8]

    # Sparse extract, within its parent.
    e = spextract(m.producers.growth)
    @test e isa SparseVector{Float64}
    @test e == [0, 5, 0, 8]

    @netfails(spextract(m.producers.growth, :x), "Not a class in the network: :x.")
    @netfails(spextract(m.producers.growth, :tops),
        "Node class :tops does not superclass :producers.")
    @argfails(spextract(m.body_mass), "Cannot sparse-extract from a root class: :species.")

end

end

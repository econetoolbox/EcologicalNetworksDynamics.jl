"Test all aspects of typical Class component, using species as an example."
module ClassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @test_err, @jl_basic_callfails, @bpfails,
    @viewfails, @propfails, addfails, @immutfails
using EcologicalNetworksDynamics.NetworkFramework: D, NF, Network, Views
using EcologicalNetworksDynamics.Framework: F, @PropertySpace
using OrderedCollections
using SparseArrays
using Test

# The data kind, view type and property spaces tested here.
const d, _D = D.Class(:species)
const Sp = @PropertySpace(species, Network)

@testset "Class component: blueprints" begin

    # Blueprints available from component.
    @test Species isa Component
    @test_disp(typeof(Species), "<Species> (component type for $Network)")
    @test_disp(Species,
        """
        Species (component for $Network, expandable from:
          Names: raw species names,
          Number: number of species,
        )\
        """)
    @test Species.Names <: Blueprint
    @test Species.Number <: Blueprint

    # ======================================================================================
    # From names.

    #---------------------------------------------------------------------------------------
    # Construct.

    # Various input types.
    bp = Species.Names([:a, :b, :c])
    @test bp.names isa Vector{Symbol}
    @test bp == Species.Names(['a', 'b', 'c']) # ::Char
    @test bp == Species.Names(["a", "b", "c"]) # ::String
    @test bp == Species.Names(split("a b c")) # ::SubString etc.
    @test bp == Species.Names(:a, 'b', "c") # Allow input as separate arguments.
    @test bp == Species.Names("abc") # Split into single-char names.
    # Implicit constructor.
    @test bp == Species([:a, :b, :c])
    @test bp == Species(['a', 'b', 'c'])
    @test bp == Species(["a", "b", "c"])
    @test bp == Species(split("a b c"))
    @test bp == Species("abc")
    @test_repr(bp, "<Species>:Names(names: [:a, :b, :c])")
    @test_disp(bp,
        """
        blueprint for <Species>: Names {
          names: [:a, :b, :c],
        }\
        """)

    # Alias to the value inside the blueprint if input type matches exactly.
    input = Symbol[:a, :b, :c]
    bp = Species(input)
    @test input === bp.names
    input[2] = :x
    @test bp.names == [:a, :x, :c]

    @bpfails(Species.Names(:a),
        Species.Names, :construct,
        (d, :a, :whole, nothing,
            "Cannot convert to `$Vector{$Symbol}`:\nInput is not iterable."))
    @jl_basic_callfails(Species(:a)) # Preserve forward compatibility.

    @bpfails(Species([:a, :b, nothing]),
        Species.Names, :construct,
        (d, nothing, (3,), nothing,
            "Cannot convert to `$Symbol`:\nConversion not implemented."))
    @test_err(Species([:a, :b, nothing]), # First time with a 1D uref.
        """
        While constructing blueprint Species.Names:
        In the provided input at [3]:
        Cannot convert to `$Symbol`:
        Conversion not implemented.
        Received: nothing  ::$Nothing\
        """)

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(Species([:a, :b, 'b']), # TODO: confusingly reports `Received: :b`.. fix?
        Species.Names, :construct,
        (d, :b, (3,), nothing, "Species 2 and 3 would both be named :b."))

    #---------------------------------------------------------------------------------------
    # Early check.

    # It is (still) ok to break values checking afterwards..
    input[3] = :x
    # .. but then expansion fails.
    addfails.@check(Model(bp), [],
        (Species.Names, :early,
            (d, :x, (3,), nothing, "Species 2 and 3 would both be named :x.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    m = Model(Species(collect("abc")))
    @test has_component(m, Species)
    @test_disp(m,
        """
        Model (alias for $(F.System){$Network}) with 1 component:
          - Species: 3 (:a, :b, :c)\
        """)

    # ======================================================================================
    # From a number, generating short distinct names.

    bp = Species.Number(5)
    @test bp.n isa Int
    @test bp == Species(5) # Directly dispatched from component.
    @test_repr(bp, "<Species>:Number(n: 5)")
    @test_disp(bp,
        """
        blueprint for <Species>: Number {
          n: 5,
        }\
        """)

    # Intrinsic check.
    @bpfails(Species(-1),
        Species.Number, :construct,
        (d, -1, :whole, nothing, "Cannot construct a negative number of species nodes."))

    # Early check.
    bp.n = -3
    addfails.@check(Model(bp), [],
        (Species.Number, :early,
            (d, -3, :whole, nothing,
                "Cannot construct a negative number of species nodes.")))

    # Expand.
    m = Model(Species(3))
    @test has_component(m, Species)
    @test_disp(m,
        """
        Model (alias for $(F.System){$Network}) with 1 component:
          - Species: 3 (:s1, :s2, :s3)\
        """)

end

@testset "Class component: properties" begin

    # Not available if the component is missing.
    @propfails(Model().species.names,
        Sp, :names, "Component <Species> is required to read this property.")
    @test_err(Model().species.names,
        """
        In property `species.names` of `$(F.System){$Network}`:
        Component <Species> is required to read this property.\
        """)

    m = Model(Species([:a, :b, :c]))

    # Names view (tested further below).
    @test m.species.names == [:a, :b, :c]
    # Number of nodes in the class.
    @test m.species.number == 3
    # Index to map labels to canonical order.
    @test m.species.index == OrderedDict(:a => 1, :b => 2, :c => 3)
    # Same within the parent class (no parent class for this root example).
    @test m.species.parent_index == OrderedDict(:a => 1, :b => 2, :c => 3)
    # Corresponding, degenerated mask.
    @test m.species.mask == [1, 1, 1]

    # Types.
    @test m.species.names isa Views.NodeNameView{D.Class(:species)[1]}
    @test m.species.mask isa Views.NodeMaskView{D.Subclass(:species, nothing)[1]}
    @test m.species.names isa AbstractVector{Symbol}
    @test m.species.mask isa AbstractVector{Bool}
    @test m.species.index isa OrderedDict{Symbol,Int}
    @test m.species.parent_index isa OrderedDict{Symbol,Int}

end

@testset "Class component: names view" begin

    View = Views.NodeNameView{d}
    bp = Species([:a, :b, :c])
    m = Model(bp)
    v = m.species.names

    @test_repr(v, "<species>[:a, :b, :c]")
    @test_disp(v,
        """
        NodeNameView<species>{Symbol} (3 values)
         :a
         :b
         :c\
        """)
    @test_err(v.a, "No property to access on views:\nTried to access :a.") # Opaque though.

    # The view has some basic vector-like interface.
    @test v == collect(v) == [:a, :b, :c] == [i for i in v]
    # The view may be extracted into a regular vector.
    e = extract(v)
    @test e isa Vector{Symbol}
    @test e == v

    # Either index with integers or labels, also converted like data input.
    @test v[1] == :a
    @test v[0x1] == :a
    @test v[:a] == :a  # (not super-useful but consistent with other views)
    @test v['b'] == :b
    @test v["c"] == :c
    @test v[split("a")...] == :a # (accept substrings as label)

    # Natural markers, ranges, boolean masks, indices lists, inherited from AbstractArray.
    @test v isa AbstractVector{Symbol}
    @test v[end] == :c
    @test v[end-1] == :b
    @test v[1:2] == [:a, :b]
    @test v[(end-1):end] == [:b, :c]
    @test v[[false, true, false]] == [:b]
    @test v[[3, 3, 3, 2, 2, 1]] == [:c, :c, :c, :b, :b, :a]
    # Special feature: convert to labels.
    @test v[['c', 'b', 'b', 'a']] == [:c, :b, :b, :a]

    # Basic bound-checking is homemade.
    @viewfails(v[-5], (d, -5, :whole, nothing, "There are 3 nodes in this class."))
    @viewfails(v[5], (d, 5, :whole, nothing, "There are 3 nodes in this class."))
    @viewfails(v[end+1], (d, 4, :whole, nothing, "There are 3 nodes in this class."))
    @viewfails(v[:x], (d, :x, :whole, nothing, "No node in this class is labeled :x."))
    # TODO: either the reports tested here provide too much information (to be tested)
    # or that information should be better exploited to produce better report.

    # Short query display.
    @test_err(v[:x],
        """
        Cannot index into <species> with [:x]:
        No node in this class is labeled :x.\
        """)

    @test_err(v[['a', 'x']],
        """
        Cannot index into <species> with [['a', 'x']]:
        In element [2] within the index:
        No node in this class is labeled :x.
        Received: 'x'  ::Char\
        """)

    # And the rest of input checking is (now) made by julia's AbstractArray.
    @test_err(v[], "BoundsError: attempt to access 3-element $View at index []")
    @test_err(v[1, 2], "BoundsError: attempt to access 3-element $View at index [1, 2]")
    @test_err(v[1, 2, 3],
        "BoundsError: attempt to access 3-element $View at index [1, 2, 3]")
    @test_err(v[true], "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(3,)], "ArgumentError: invalid index: (3,) of type Tuple{$Int}")
    @test_err(v[0x8000000000000000], "InexactError: convert($Int, 0x8000000000000000)")
    @test_err(v[(end-1):(end+1)],
        "BoundsError: attempt to access 3-element $View at index [2:4]")
    @test_err(v[Bool[0, 1]],
        "BoundsError: attempt to access 3-element $View at index [2-element Vector{Bool}]")
    # (we used to have better error messages than julia's though, nevermind X)

    # Immutable.
    @immutfails((v[1] = :u), View)
    @immutfails((v[:a] = :u), View)
    @immutfails((v[:a] = 2), View)
    # This takes priority over other indexing guards.
    @immutfails((v[] = 2), View)
    @immutfails((v[1, 2] = 2), View)
    @immutfails((v[nothing] = 2), View)

    @test_err((v[1] = :u), "Cannot change <species> nodes names once they have been set.")

    # Although the *blueprint* can be mutated.
    bp.names[2] = :x
    @test Model(bp).species.names == [:a, :x, :c]

end

@testset "Class component: expansion semantics" begin

    # This was indirectly checked above (from display and views).
    # Check it explicitly now that the views are proven to work.
    @test Model(Species("abc")).species.names == [:a, :b, :c]
    @test Model(Species(3)).species.names == [:s1, :s2, :s3]

    # Degenerate class with no nodes.
    function empty(m)
        @test_disp(m,
            """
            Model (alias for $(F.System){$Network}) with 1 component:
              - Species: 0 ()\
            """)
        @test m.species.names == []
        @test m.species.number == 0
        @test m.species.index == OrderedDict()
        @test m.species.parent_index == OrderedDict()
        @test m.species.mask == []
    end
    empty(Model(Species([])))
    empty(Model(Species(0)))

end

end

"""
Test all aspects of typical Class component,
using species as an example, but without testing anything specific to species.
Anything specific to species will be tested in a dedicated file.
"""
module ClassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @test_err, @jl_basic_callfails, @bpfails,
    @mutfails, @propfails, addfails
using EcologicalNetworksDynamics.NetworkFramework: EN, D, Network, Views
using EcologicalNetworksDynamics.Framework: F, @PropertySpace
# The data kind, view type and property spaces tested here.
const d, _D = D.Class(:species)
const View = Views.NodeNameView{d}
const Sp = @PropertySpace(species, Network)
using OrderedCollections
using Test

@testset "Class component: blueprints" begin

    # Blueprints available from component.
    @test Species isa EN.Component
    @test_disp(typeof(Species), "<Species> (component type for $Network)")
    @test_disp(Species,
        """
        Species (component for $Network, expandable from:
          Names: raw species names,
          Number: number of species,
        )\
        """)
    @test Species.Names <: EN.Blueprint
    @test Species.Number <: EN.Blueprint

    # ======================================================================================
    # From names.

    #---------------------------------------------------------------------------------------
    # Construct.

    # Various input types.
    bp = Species.Names([:a, :b, :c])
    @test bp == Species.Names(['a', 'b', 'c']) # ::Char
    @test bp == Species.Names(["a", "b", "c"]) # ::String
    @test bp == Species.Names(split("a b c")) # ::SubString etc.
    @test bp == Species.Names(:a, 'b', "c") # Allow input as separate arguments.
    # Implicit constructor.
    @test bp == Species([:a, :b, :c])
    @test bp == Species(['a', 'b', 'c'])
    @test bp == Species(["a", "b", "c"])
    @test bp == Species(split("a b c"))
    @test bp == Species(:a, 'b', "c")
    @test_repr(bp, "<Species>:Names(names: [:a, :b, :c])")
    @test_disp( bp,
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

    @bpfails(Species(:a),
        Species.Names, :construct, nothing,
        (nothing, :whole, :convert, Vector{Symbol}, :a, "Input is not iterable."))
    @jl_basic_callfails(Species(5; a = 5))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.
    @bpfails(Species([:a, :b, :b]),
        Species.Names, :construct, nothing,
        (nothing, 3, :check, :b, "Species 2 and 3 would both be named :b."))
    @test_err(Species([:a, :b, :b]), # First time with a 1D index.
        """
        While constructing blueprint Species.Names:
        In the provided value at [3]:
        Species 2 and 3 would both be named :b.
        Received: :b ::Symbol\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    # It is (still) ok to break values checking afterwards..
    input[3] = :x
    # .. but then expansion fails.
    addfails.@check(Model(bp), [],
        (Species.Names, :early, nothing,
            (nothing, 3, :check, :x, "Species 2 and 3 would both be named :x.")))

    # Expand.
    m = Model(Species(collect("abc")))
    @test_disp(m,
        """
        Model (alias for $(F.System){$Network}) with 1 component:
          - Species: 3 (:a, :b, :c)\
        """)

    # ======================================================================================
    # From a number, generating short distinct names.

    bp = Species.Number(5)
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
        Species.Number, :construct, nothing,
        (nothing, :whole, :check, -1,
            "Cannot construct a negative number of species nodes."))

    # Early check.
    bp.n = -3
    addfails.@check(Model(bp), [],
        (Species.Number, :early, nothing,
            (nothing, :whole, :check, -3,
                "Cannot construct a negative number of species nodes.")))

    # Expand.
    m = Model(Species(3))
    @test_disp(
        m,
        """
        Model (alias for $(F.System){$Network}) with 1 component:
          - Species: 3 (:s1, :s2, :s3)\
        """,
    )

end

@testset "Class component: views" begin

    # No view if the component is missing.
    @propfails(Model().species.names,
        Sp, :names, "Component $(EN._Species) is required to read this property.")

    # The names property becomes available as a view.
    m = Model(Species(:a, :b, :c))
    v = m.species.names

    @test v isa View
    @test v isa AbstractVector{Symbol}
    @test_repr(v, "<species>[:a, :b, :c]")
    @test_disp(v,
        """
        NodeNameView<species>{Symbol} (3 values)
         :a
         :b
         :c\
        """)

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

    # The component enables various other properties:

    # Number of nodes in the class.
    @test m.species.number == 3
    # Index to map labels to canonical order.
    @test m.species.index == OrderedDict(:a => 1, :b => 2, :c => 3)
    # Same within the parent class (no parent class for this root example).
    @test m.species.parent_index == OrderedDict(:a => 1, :b => 2, :c => 3)

    # Mask within the parent class (no parent class with this root example).
    K = Views.NodeMaskView{D.Subclass(:species, nothing)[1]}
    k = m.species.mask
    @test k isa K
    @test k isa AbstractVector{Bool}
    @test k[1] && k[2] && k[3]
    @test k[:a] && k[:b] && k[:c]
    @test k == Bool[1, 1, 1]
    @test k[1:2] == Bool[1, 1]
    @test k[(end-1):end] == Bool[1, 1]
    @test_repr(k, "<::species>[1, 1, 1]")
    @test_disp(
        k,
        """
        NodeMaskView<::species>{Bool} (3/3 values)
         1
         1
         1\
        """,
    )

end

# HERE: almost finished refreshing this file.
@testset "Class component: immutable" begin

    bp = Species(:a, :b, :c)
    m = Model(bp)
    v = m.species.names

    # Immutable.
    @mutfails((v[1] = :u), d, :mutate, m, ())
    @mutfails((v[:a] = :u), View)
    @mutfails((v[:a] = 2), View)
    # This takes priority over other indexing guards.
    @mutfails((v[] = 2), View)
    @mutfails((v[1, 2] = 2), View)
    @mutfails((v[nothing] = 2), View)

    # What the user gets.
    @test_err(
        () -> v[1] = :u,
        "Cannot change <species> nodes names once they have been set.",
    )

    # But the *blueprint* can be mutated.
    bp.names[2] = :x
    @test Model(bp).species.names == [:a, :x, :c]

end

end

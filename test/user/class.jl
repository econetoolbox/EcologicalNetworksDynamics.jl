"""
Test all aspects of typical Class component,
using Species as an example, but without testing anything specific to species.
Anything specific to species will be tested in a dedicated file.
"""
module ClassTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, F, D, Network, Views
import Main: is_repr, is_disp, @inputfails, @sysfails, @indexfails, Value
const View = Views.NodeNameView{D.Class(:species)} # Tested view type.

@testset "Class component: blueprints" begin

    # Blueprints available from component.
    @test Species isa EN.Component
    @test is_repr(Species, "Species")
    @test is_disp(
        Species,
        """
        Species (component for $Network, expandable from:
          Names: raw species names,
          Number: number of species,
        )\
        """,
    )
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
    @test is_repr(bp, "<Species>:Names(names: [:a, :b, :c])")
    @test is_disp(
        bp,
        """
        blueprint for <Species>: Names {
          names: [:a, :b, :c],
        }\
        """,
    )

    # Alias to the value inside the blueprint if input type matches exactly.
    input = Symbol[:a, :b, :c]
    bp = Species(input)
    @test input === bp.names
    input[2] = :x
    @test bp.names == [:a, :x, :c]

    #---------------------------------------------------------------------------------------
    # Intrinsic check.
    @inputfails(
        Species([:a, :b, :b]),
        "When constructing blueprint for <species>:\n\
         Species 2 and 3 would both be named :b."
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    # It is (still) ok to break values checking afterwards..
    input[3] = :x
    # .. but then expansion fails.
    @sysfails(
        Model(bp),
        Check(
            early,
            [Species.Names],
            "When checking <species> blueprint data:\n\
             Species 2 and 3 would both be named :x.",
        )
    )

    # Expand.
    m = Model(Species(collect("abc")))
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(EN.Network)}) with 1 component:
          - Species: 3 (:a, :b, :c)\
        """,
    )

    # ======================================================================================
    # From a number, generating short distinct names.

    bp = Species.Number(5)
    @test bp == Species(5) # Directly dispatched from component.
    @test is_repr(bp, "<Species>:Number(n: 5)")
    @test is_disp(
        bp,
        """
        blueprint for <Species>: Number {
          n: 5,
        }\
        """,
    )

    # Intrinsic check.
    @inputfails(
        Species(-1),
        "When constructing blueprint for <species>:\n\
         Cannot construct a negative number of species.",
        -1,
    )

    # Early check.
    bp.n = -3
    @sysfails(
        Model(bp),
        Check(
            early,
            [Species.Number],
            "When checking <species> blueprint data:\n\
             Cannot construct a negative number of species.\n\
             Received: -3 ::Int64",
        ),
    )

    # Expand.
    m = Model(Species(3))
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(EN.Network)}) with 1 component:
          - Species: 3 (:s1, :s2, :s3)\
        """,
    )

end

@testset "Class component: views" begin

    # No view if the component is missing.
    @sysfails(
        Model().species.names,
        Property(
            species.names,
            "Component $(EN._Species) is required to read this property.",
        ),
    )

    # The names property becomes available as a view.
    m = Model(Species(:a, :b, :c))
    v = m.species.names

    @test v isa View
    @test v isa AbstractVector{Symbol}
    @test is_repr(v, "<species>[:a, :b, :c]")
    @test is_disp(
        v,
        """
        NodeNameView<species>{Symbol} (3 values)
         :a
         :b
         :c\
        """,
    )

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
    K = Views.NodeMaskView{D.Subclass(:species, nothing)}
    k = m.species.mask
    @test k isa K
    @test k isa AbstractVector{Bool}
    @test k[1] && k[2] && k[3]
    @test k[:a] && k[:b] && k[:c]
    @test k == Bool[1, 1, 1]
    @test k[1:2] == Bool[1, 1]
    @test k[end-1:end] == Bool[1, 1]
    @test is_repr(k, "<::species>[1, 1, 1]")
    @test is_disp(
        k,
        """
        NodeMaskView<::species>{Bool} (3/3 values)
         1
         1
         1\
        """,
    )

    # The above makes more sense with a non-root class, like producers here.
    m = Model(Foodweb([:a => (:b, :c), :d => :e]))
    @test m.producers.names == [:b, :c, :e]
    @test m.producers.number == 3
    @test m.producers.index == OrderedDict(:b => 1, :c => 2, :e => 3)
    @test m.producers.parent_index == OrderedDict(:b => 2, :c => 3, :e => 5)
    k = m.producers.mask
    @test k == [0, 1, 1, 0, 1]
    @test k[2:4] == [1, 1, 0]

end

@testset "Class component: immutable" begin

    bp = Species(collect("abc"))
    m = Model(bp)
    v = m.species.names

    # Immutable.
    mess = "Cannot change :species nodes names after they have been set."
    @indexfails((v[1] = :u), View, mess)
    @indexfails((v[:a] = :u), View, mess)
    @indexfails((v[:a] = 2), View, mess)
    # This takes priority over indexing semantics.
    @indexfails((v[] = 2), View, mess)
    @indexfails((v[1, 2] = 2), View, mess)
    @indexfails((v[nothing] = 2), View, mess)

    # But the *blueprint* can be mutated.
    bp.names[2] = :x
    @test Model(bp).species.names == [:a, :x, :c]

end

end

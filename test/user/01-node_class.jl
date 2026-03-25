"""
Test all aspects of typical NodeClass component,
using Species as an example, but without testing anything specific to species.
Anything specific to species will be tested in a dedicated file.
"""
module NodeClassTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, Network, Views, NodeClass
import Main: is_repr, is_disp, @viewfails, @sysfails
const Value = Network # To have @sysfails work.

@testset "Typical NodeClass component" begin

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

    # Construct from names, converted from various input types.
    bp = Species.Names([:a, :b, :c])
    @test bp == Species.Names(['a', 'b', 'c'])
    @test bp == Species.Names(["a", "b", "c"])
    # Implbicit constructor.
    @test bp == Species([:a, :b, :c])
    @test bp == Species(['a', 'b', 'c'])
    @test bp == Species(["a", "b", "c"])
    @test is_repr(bp, "<Species>:Names(names: [:a, :b, :c])")
    @test is_disp(
        bp,
        """
        blueprint for <Species>: Names {
          names: [:a, :b, :c],
        }\
        """,
    )

    # Expand into a name component.
    m = Model(bp)

    # The names property becomes available as a view.
    V = Views.NodesNamesView{NodeClass(:species)}
    v = m.species.names
    @test v isa V
    @test v isa AbstractVector{Symbol}
    @test is_repr(v, "<species>[:a, :b, :c]")
    @test is_disp(
        v,
        """
        NodesNamesView<species>{Symbol} (3 values)
         :a
         :b
         :c\
        """,
    )

    # The view has some basic vector-like interface.
    @test v == collect(v) == [:a, :b, :c] == [i for i in v]

    # Index with either integers or labels.
    @test v[1] == :a
    @test v[1:2] == [:a, :b]
    @test v[2:end] == [:b, :c]
    @test v[:b] == :b # (not super-useful but consistent with other views)

    # Wrong access.
    @viewfails(v[0], V, "Cannot index with [0] into a view with 3 :species nodes.")
    @viewfails(v[4], V, "Cannot index with [4] into a view with 3 :species nodes.")
    @viewfails(
        v[:x],
        V,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c]."
    )
    @viewfails(v[], V, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2], V, "Cannot index into nodes with 2 dimensions: [1, 2].")

    # Immutable.
    mess = "Cannot change :species nodes names after they have been set."
    @viewfails((v[1] = :u), V, mess)
    @viewfails((v[:a] = :u), V, mess)
    @viewfails((v[:a] = 2), V, mess)

    # But the *blueprint* can be mutated.
    bp.names[2] = :x
    @test Model(bp).species.names == [:a, :x, :c]

    # Fail construct from names.
    @sysfails(
        Model(Species([:a, :b, :b])),
        Check(early, [Species.Names], "Species 3 and 2 are both named :b.")
    )

    # Construct from a number, generating short distinct names.
    bp = Species.Number(5)
    @test bp == Species(5) # Directly from component.
    @test is_repr(bp, "<Species>:Number(n: 5)")
    @test is_disp(
        bp,
        """
        blueprint for <Species>: Number {
          n: 5,
        }\
        """,
    )

    # Expand into the same component.
    m = Model(bp)
    @test m.species.names == [:s1, :s2, :s3, :s4, :s5]

    # Mutating blueprint is always possible.
    bp.n = 3
    @test Model(bp).species.names == [:s1, :s2, :s3]

    # Fail construct from numbers.
    @sysfails(
        Model(Species(-3)),
        Check(
            early,
            [Species.Number],
            "Cannot construct a negative number of species: -3.",
        ),
    )

    # The component enables various other properties.
    m = Model(Species(collect("abc")))
    # Number of nodes in the class.
    @test m.species.number == 3
    # Index to map labels to canonical order.
    @test m.species.index == OrderedDict(:a => 1, :b => 2, :c => 3)
    # Same within the parent class (no parent class for this root example).
    @test m.species.parent_index == OrderedDict(:a => 1, :b => 2, :c => 3)

    # Mask within the parent class (no parent class with this root example).
    k = m.species.mask
    @test k isa Views.NodesMaskView
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
        NodesMaskView<::species>{Bool} (3/3 values)
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
    @test m.producers.mask == [0, 1, 1, 0, 1]

end


end

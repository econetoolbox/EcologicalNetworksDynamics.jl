"""
Test all aspects of typical NodeField component,
using BodyMass as an example but without testing anything specific to BodyMass.
Anything specific to BodyMass will be tested in a dedicated file.
"""
module NodeFieldTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
using OrderedCollections
import EcologicalNetworksDynamics: EN, Network, Views, NodeField
import Main: is_repr, is_disp, @viewfails, @sysfails
const Value = Network # To have @sysfails work.
const V = Views.NodesDataView{NodeField(:species, :body_mass),Float64} # Tested view type.

@testset "Typical NodeField component" begin

    # Blueprints available from component.
    @test BodyMass isa EN.Component
    @test is_repr(BodyMass, "BodyMass")
    @test is_disp(
        BodyMass,
        """
        BodyMass (component for Network, expandable from:
          Raw: raw values,
          Map: [species => body_mass] map,
          Flat: uniform value,
          Z: trophic levels,
        )\
        """,
    )
    @test BodyMass.Raw <: EN.Blueprint
    @test BodyMass.Map <: EN.Blueprint
    @test BodyMass.Flat <: EN.Blueprint
    @test BodyMass.Z <: EN.Blueprint # So the extension point worked, but test Z elsewhere.

    # Construct from raw values, regardless of input type.
    bp = BodyMass.Raw([4.0, 5.0, 6.0])
    @test bp == BodyMass.Raw([4, 5, 6])
    @test BodyMass.Raw(Bool[1, 0, 1]) == BodyMass.Raw([1.0, 0.0, 1.0])
    # Implbicit constructor.
    @test bp == BodyMass([4.0, 5.0, 6.0])
    @test bp == BodyMass([4, 5, 6])
    @test BodyMass(Bool[1, 0, 1]) == BodyMass([1.0, 0.0, 1.0])
    @test is_repr(bp, "<BodyMass>:Raw(body_mass: [4.0, 5.0, 6.0], species: <Species>)")
    @test is_disp(
        bp,
        """
        blueprint for <BodyMass>: Raw {
          body_mass: [4.0, 5.0, 6.0],
          species: <implied blueprint for <Species>>,
        }\
        """,
    )

    # Expand into a field component.
    m = Model(bp)

    # Brings dummy node class names if not specified.
    @test m.species.names == [:s1, :s2, :s3]

    # Or else we do specify during expansion.
    m = Model(Species([:a, :b, :c]), bp)
    @test m.species.names == [:a, :b, :c]

    # Or else we do specify within the blueprint itself.
    bp.species = [:a, :b, :c]
    m = Model(bp)
    @test m.species.names == [:a, :b, :c]

    # The names property becomes available as a view.
    v = m.body_mass
    @test v isa V
    @test v isa AbstractVector{Float64}
    @test is_repr(v, "<species:body_mass>[4.0, 5.0, 6.0]")
    @test is_disp(
        v,
        """
        NodesDataView<species:body_mass>{Float64} (3 values)
         4.0
         5.0
         6.0\
        """,
    )

    # The view has some basic vector-like interface.
    @test v == collect(v) == [4, 5, 6] == [i for i in v]

    # Index with either integers or labels.
    @test v[1] == 4
    @test v[1:2] == [4, 5]
    @test v[end-1:end] == [5, 6]
    @test v[:b] == 5
    @viewfails(
        v[nothing],
        V,
        "Views are indexed with indices (::Int) or labels (::Symbol). \
         Cannot index with: nothing ::Nothing."
    )
    @viewfails(v[0], V, "Cannot index with [0] into a class with 3 :species nodes.")
    @viewfails(v[4], V, "Cannot index with [4] into a class with 3 :species nodes.")
    @viewfails(
        v[:x],
        V,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c]."
    )
    @viewfails(v[], V, "Cannot index into nodes with 0 dimensions: [].")
    @viewfails(v[1, 2], V, "Cannot index into nodes with 2 dimensions: [1, 2].")

    error("HERE: resume testing.")
    ######################################################################################
    # vvvvv only placeholders below  vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
    ######################################################################################

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
        Model(BodyMass([:a, :b, :b])),
        Check(early, [BodyMass.Names], "Species 3 and 2 are both named :b.")
    )

    # Construct from a number, generating short distinct names.
    bp = BodyMass.Number(5)
    @test bp == BodyMass(5) # Directly from component.
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
        Model(BodyMass(-3)),
        Check(
            early,
            [BodyMass.Number],
            "Cannot construct a negative number of species: -3.",
        ),
    )

    # Various implicit/explicit forms for brought field in constructors.
    bp = BodyMass.Matrix(A, Species(2))
    @test bp == BodyMass.Matrix(A; species = Species(2))
    @test bp == BodyMass.Matrix(A, Species(2))
    @test bp == BodyMass.Matrix(A; species = 2)
    @test bp == BodyMass.Matrix(A, 2)
    @test bp == BodyMass(A; species = Species(2))
    @test bp == BodyMass(A; species = 2)
    @test bp == BodyMass(A, Species(2))
    @test bp == BodyMass(A, 2)

    # The component enables various other properties.
    m = Model(BodyMass(collect("abc")))
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

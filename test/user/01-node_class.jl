# Test all aspects of typical NodeClass component,
# using Species as an example, but without testing anything specific to species.
# Anything specific to species will be tested in a dedicated file.
module NodeClassTest

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using Test
import EcologicalNetworksDynamics: Network, Views, NodeClass
import Main: is_repr, is_disp, @viewfails, @sysfails
const Value = Network # To have @sysfails work.

@testset "Typical NodeClass component" begin

    # Blueprints available from component.
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

    # Construct from names.
    bp = Species.Names([:a, :b, :c])
    m = Model(bp)

    # The names property becomes available as a view.
    v = m.species.names
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
    V = Views.NodesNamesView{NodeClass(:species)}
    @viewfails(v[0], V, "Cannot index with [0] into a view with 3 :species nodes.")
    @viewfails(v[4], V, "Cannot index with [4] into a view with 3 :species nodes.")
    @viewfails(
        v[:x],
        V,
        "Label does not refer to a node in :species class: :x.\n\
         Valid labels: [:a, :b, :c]."
    )

    # Immutable.
    mess = "Cannot change :species nodes names after they have been set."
    @viewfails((v[1] = :u), V, mess)
    @viewfails((v[:a] = :u), V, mess)
    @viewfails((v[:a] = 2), V, mess)

    # Failed construct from names.
    @sysfails(
        Model(Species.Names([:a, :b, :b])),
        Check(early, [Species.Names], "Species 3 and 2 are both named :b.")
    )


    # Construct from a number, generating short names.
    bp = Species.Number(5)
    m = Model(bp)
    @test m.species.names == [:s1, :s2, :s3, :s4, :s5]

    # Construct directly from the component singleton.
    bp = Species([:a, :b, :c])
    @test is_repr(bp, "<Species>:Names(names: [:a, :b, :c])")
    @test is_disp(
        bp,
        """
        blueprint for <Species>: Names {
          names: [:a, :b, :c],
        }\
        """,
    )

    # Convert from various input types.
    @test Species(['a', 'b', 'c']) == bp
    @test Species(["a", "b", "c"]) == bp
    # HERE: keep testing.

end


end

module TestViews

using EcologicalNetworksDynamics

using Test
using Main.TestUtils
using Main: @viewfails, @labelfails, @argfails, @failswith

const EN = EcologicalNetworksDynamics
const Views = EN.Views

# XXX: Test:
# - [x] Nodes names.
# - [x] Nodes mask.
# - [x] Nodes data.
# - [ ] Nodes expanded data.
# - [ ] Edges mask.
# - [ ] Edges data.

fw = Foodweb([:a => :b, :b => :c])
m = Model(fw, BodyMass([1, 2, 3]))

for (v, V, exp, setname, nodename) in [
    (m.species.names, Views.NodesNamesView, [:a, :b, :c], "names", :species),
    (m.producers.mask, Views.NodesMaskView, sparse(Bool[0, 0, 1]), "mask", :producers),
    (m.body_mass, Views.NodesDataView{Float64}, [1.0, 2.0, 3.0], "data", :species),
]
    @testset "Nodes $setname view generic interface." begin

        # Use as a vector.
        @test eltype(v) === eltype(exp)
        @test v[1] == exp[1]
        @test v[2] == exp[2]
        @test v[3] == exp[3]
        @test v[2:3] == exp[2:3]
        @test v == extract(v) == collect(v) == exp

        # Access with labels.
        @test v[:a] == exp[1]
        @test v[:b] == exp[2]
        @test v[:c] == exp[3]

        # Guard index.
        for i in [-5, 0, 5]
            @viewfails(
                v[i],
                V,
                "Cannot index with [$i] into a view with 3 :$nodename nodes."
            )
        end
        @labelfails(v[:x], x, species)

        # Guard against invalid dimensions index.
        e = "Cannot index into nodes with 0 dimensions: []."
        @viewfails(v[], V, e)
        @viewfails(v[] = 1, V, e)

        e = "Cannot index into nodes with 2 dimensions: [1, 2]."
        @viewfails(v[1, 2], V, e)
        @viewfails(v[1, 2] = 1, V, e)

        e = "Cannot index into nodes with 2 dimensions: [:a, :b]."
        @viewfails(v[:a, :b], V, e)
        @viewfails(v[:a, :b] = 1, V, e)

    end
end

# ==========================================================================================
# Names.

@testset "Nodes names view specific interface." begin

    V = EN.Views.NodesNamesView
    v = m.species.names

    # Not a vector.
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

    # Read-only.
    @viewfails(
        v[1] = :aa,
        V,
        "Cannot change :species nodes names after they have been set."
    )
    @viewfails(
        v[2:3] .= :aa,
        V,
        "Cannot change :species nodes names after they have been set."
    )

end

# ==========================================================================================
# Mask.

@testset "Nodes mask view specific interface." begin

    V = EN.Views.NodesMaskView
    v = m.producers.mask

    # Not a vector.
    @test is_repr(v, "<species:producers>[·, ·, 1]")
    @test is_disp(
        v,
        """
        NodesMaskView<species:producers>{Bool} (1/3 value)
         ·
         ·
         1\
        """,
    )

    # Extract to a sparse vector.
    @test extract(v) isa SparseVector{Bool}

    # Read-only.
    @viewfails(v[1] = true, V, "Cannot change :producers nodes mask after it has been set.")
    @viewfails(
        v[2:3] .= true,
        V,
        "Cannot change :producers nodes mask after it has been set."
    )

    # Exposed with corresponding sub-classes.
    @test m.producers.names == [:c]
    @test m.consumers.names == [:a, :b]

end

# ==========================================================================================
# Data.

@testset "Nodes data view specific interface." begin

    V = EN.Views.NodesDataView{Float64}
    bm = m.body_mass

    # Not a vector.
    @test is_repr(bm, "<species:body_mass>[1.0, 2.0, 3.0]")
    @test is_disp(
        bm,
        """
        NodesDataView<species:body_mass>{Float64} (3 values)
         1.0
         2.0
         3.0\
        """,
    )

    # Write through the view.
    other_model = copy(m)
    other_view = m.M
    bm[1] = 10 # Mutate.
    @test bm[1] == other_view[1] == m.M[1] == 10 # Model impacted and all other views.
    @test other_model.M[1] == 1 # Forked model unchanged.

    bm[1:2] .= 20
    @test bm == [20, 20, 3]
    bm .*= 10
    @test bm == [200, 200, 30]

    bm[:b] = 5
    @test bm[2] == bm[:b] == 5

    bm .= [1, 2, 3] # Reset
    @test bm == [1.0, 2.0, 3.0]

    #---------------------------------------------------------------------------------------
    # Guard rhs.
    WE = EN.Views.WriteError

    @failswith(
        (m.M[1] = "a"),
        WE(
            "could not convert to a value of type Float64 (see stacktrace below)",
            :body_mass,
            1,
            "a",
        )
    )

    @failswith(
        (m.M[1] = 'a'), # Special-case.
        WE(
            "would not automatically convert Char to a value of type Float64",
            :body_mass,
            1,
            'a',
        )
    )

    @argfails(
        (m.M[2:3] = 10),
        "indexed assignment with a single value to possibly many locations \
         is not supported; perhaps use broadcasting `.=` instead?",
    )

    # TODO: Essentially same error as above, but message more confusing.
    @failswith(
        (m.M[2:3] *= 10),
        WE(
            "could not convert to a value of type Float64 (see stacktrace below)",
            :body_mass,
            2:3,
            [20.0, 30.0],
        )
    )

    # Also per-field special guard.
    @failswith((m.M[1] = -10), WE("not a positive value", :body_mass, 1, -10.0))

    @failswith((bm[2:3] .*= -10), WE("not a positive value", :body_mass, 2, -20.0))

end

end

module TestViews

using EcologicalNetworksDynamics

using Test
using Main.TestUtils
using Main: @viewfails, @labelfails, @argfails, @failswith

const EN = EcologicalNetworksDynamics

@testset "Writeable nodes view." begin

    V = EN.Views.NodesDataView{Float64}

    # Get a graphview type.
    fw = Foodweb([:a => :b, :b => :c])
    m = Model(fw, BodyMass([1, 2, 3]))
    bm = m.body_mass

    # Use as a vector.
    @test bm[1] == 1
    @test bm[2] == 2
    @test bm[3] == 3
    @test bm[2:3] == [2, 3]
    @test bm == collect(bm) == [1, 2, 3]

    # But it's not.
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

    # Access with labels.
    @test bm[:a] == 1
    @test bm[:b] == 2
    @test bm[:c] == 3

    # Guard index.
    for i in [-5, 0, 5]
        @viewfails(bm[i], V, "Cannot index with [$i] into a view with 3 :species nodes.")
    end
    @labelfails(bm[:x], x, species)

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

    # Guard against invalid dimensions index.
    e = "Cannot index into nodes with 0 dimensions: []."
    @viewfails(bm[], V, e)
    @viewfails(bm[] = 1, V, e)

    e = "Cannot index into nodes with 2 dimensions: [1, 2]."
    @viewfails(bm[1, 2], V, e)
    @viewfails(bm[1, 2] = 1, V, e)

    e = "Cannot index into nodes with 2 dimensions: [:a, :b]."
    @viewfails(bm[:a, :b], V, e)
    @viewfails(bm[:a, :b] = 1, V, e)

    #---------------------------------------------------------------------------------------
    # Guard rhs.
    WE = EN.Views.WriteError

    m = Model(fw, BodyMass([1, 2, 3]))
    bm = m.body_mass

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

# HERE: also test NameView + Mask + Expanded for nodes and Data + Mask for edges.

end

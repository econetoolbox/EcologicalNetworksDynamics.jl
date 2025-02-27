module TestGraphViews
using EcologicalNetworksDynamics
using Test
using ..TestUser

const EN = EcologicalNetworksDynamics
import .EN: WriteError

@testset "Writeable nodes view." begin

    # Use this one as a typical example.
    BM = EN.BodyMasses

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
    @test repr(bm) == "[1.0, 2.0, 3.0]"
    @test repr(MIME("text/plain"), bm) == """
        3-element $BM:
         1.0
         2.0
         3.0\
    """

    # Access with labels.
    @test bm[:a] == 1
    @test bm[:b] == 2
    @test bm[:c] == 3

    # Guard index.
    for i in [-5, 0, 5]
        @viewfails(
            bm[i],
            BM,
            "Species index [$i] is off-bounds for a view into 3 nodes data."
        )
    end

    @viewfails(
        bm[:x],
        BM,
        "Invalid species node label. \
         Expected either :a, :b or :c, got instead: :x."
    )

    # Write through the view.
    bm[1] = 10
    @test bm[1] == m._value._foodweb.M[1] == 10
    bm[1:2] .= 20
    @test bm == [20, 20, 3]
    bm .*= 10
    @test bm == [200, 200, 30]

    bm[:b] = 5
    @test bm[2] == bm[:b] == 5

    # Guard against invalid dimensions index.
    m = "Nodes data are 1-dimensional: \
         cannot access species data values with 0 index: []."
    @viewfails(bm[], BM, m)
    @viewfails(bm[] = 1, BM, m)

    m = "Nodes data are 1-dimensional: \
         cannot access species data values with 2 indices: [1, 2]."
    @viewfails(bm[1, 2], BM, m)
    @viewfails(bm[1, 2] = 1, BM, m)

    m = "Nodes data are 1-dimensional: \
         cannot access species data values with 2 labels: [:a, :b]."
    @viewfails(bm[:a, :b], BM, m)
    @viewfails(bm[:a, :b] = 1, BM, m)

    # Guard rhs.
    @failswith((bm[1] = 'a'), WriteError("not a value of type Real", :body_mass, (1,), 'a'))
    @failswith(
        (bm[2:3] *= -10),
        WriteError("Not a positive value: M[2] = -50.0.", :body_mass, (2,), -50)
    )

end

end

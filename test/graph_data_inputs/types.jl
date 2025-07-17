module Types
using Test
using EcologicalNetworksDynamics.GraphDataInputs
using Main.TestFailures
using OrderedCollections

@testset "Graph data input types." begin

    # ======================================================================================
    # Check convenience macro type expansion.

    U = Union{Symbol,Float64,Vector{Float64}}
    @test U === @GraphData YSV{Float64}
    @test U === @GraphData {YSV}{Float64}
    @test U === @GraphData {Sym, Scal, Vec}{Float64}
    @test U === @GraphData {Symbol, Scalar, Vector}{Float64}

    # Convenience symbol only.
    @test Symbol == @GraphData Y{}
    @test Symbol == @GraphData {Symbol}{}
    @test Symbol == @GraphData Symbol{}
    @test Symbol == @GraphData YY{}

    # Maps and Adjacencies + test aliases.
    for K in [
        @GraphData(K{Float64}),
        @GraphData({Map}{Float64}),
        @GraphData(Map{Float64}),
        @GraphData({K}{Float64}),
    ]
        @test K == OrderedDict{I,Float64} where {I}
        @test K{Symbol} == OrderedDict{Symbol,Float64}
    end

    for A in [
        @GraphData(A{Float64}),
        @GraphData({Adjacency}{Float64}),
        @GraphData(Adjacency{Float64}),
        @GraphData(Adj{Float64}),
        @GraphData({A}{Float64}),
    ]
        @test A == OrderedDict{I,OrderedDict{I,Float64}} where {I}
        @test A{Symbol} == OrderedDict{Symbol,OrderedDict{Symbol,Float64}}
    end

    # Special boolean case.
    for K in [
        @GraphData(K{:bin}),
        @GraphData(Map{:bin}),
        @GraphData({Map}{:bin}),
        @GraphData({K}{:bin}),
    ]
        @test K == OrderedSet
        @test K{Int64} == OrderedSet{Int64}
    end

    A = @GraphData A{:bin}
    @test A == OrderedDict{I,OrderedSet{I}} where {I}
    @test A{Int64} == OrderedDict{Int64,OrderedSet{Int64}}

    U = @GraphData YSVK{:bin}
    @test U == Union{Bool,Symbol,Vector{Bool},OrderedSet}

    U = @GraphData YSMA{:bin}
    @test U == Union{Bool,Symbol,Matrix{Bool},OrderedDict{I,OrderedSet{I}} where {I}}

    # ======================================================================================
    # Or invalid uses.
    @xargfails(
        (@GraphData XYZ{Float64}),
        ["The received symbol :X is not a valid type alias among:\n\
          $OrderedDict{Any, Vector{Symbol}} with 8 entries:\n  \
            Symbol => [:Symbol, :Sym, :Y]\n  \
            :Scalar => [:Scalar, :Scal, :S]\n  \
            Vector => [:Vector, :Vec, :V]\n  \
            Matrix => [:Matrix, :Mat, :M]\n  \
            SparseVector => [:SparseVector, :SpVec, :N]\n  \
            SparseMatrixCSC{T, Int64} where T => [:SparseMatrix, :SpMat, :E]\n  \
            :Map => [:Map, :K]\n  \
            :Adjacency => [:Adjacency, :Adj, :A]"],
    )
    @xargfails(
        (@GraphData {X, Y, Z}{Float64}),
        ["The received symbol :X is not a valid type alias"],
    )
    @xargfails(
        (@GraphData {Y, 4 + 5, V}{Float64}),
        ["The received symbol Symbol(\"4 + 5\") is not a valid type alias"],
    )
    @xargfails(
        (@GraphData (4 + 5){Float64}),
        [
            "Invalid macro input at",
            "Expected a braced-list of type aliases among:",
            "Received instead: :(4 + 5).",
        ],
    )
    @xargfails((@GraphData YA{}), ["No type provided."])
    @xargfails(
        (@GraphData nope),
        [
            "Invalid @GraphData input at",
            "Expected @GraphData {aliases...}{Type}. Got :nope.",
        ],
    )

end

end

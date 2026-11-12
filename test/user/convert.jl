module Convert

using EcologicalNetworksDynamics.NetworkFramework:
    NF, SparseMatrix, Map, Adjacency, BinMap, BinAdjacency, convert, try_convert
# /!\ `convert !== Base.convert` in this module.

using EcologicalNetworksDynamics.Tests: @test_err, @checkfails, @convfails

using Test
using SparseArrays
using OrderedCollections

struct _Alias end
Alias = _Alias() # Use as an unambiguous keyword.

same_type_value(a, b) = a isa typeof(b) && a == b
aliased(a, b) = a === b
function conv(T, pairs...) # Either.
    for (input, expected) in pairs
        actual = convert(T, input)
        match = if expected isa _Alias
            aliased(input, actual)
        else
            same_type_value(expected, actual)
        end
        if !match
            println("expected: $expected ::$(typeof(expected))")
            println("actual  : $actual ::$(typeof(actual))")
        end
        @test match
    end
    true
end

# Try with arbitrary iterators.
idmap(x) = Iterators.map(identity, x) # Size known.
filt(x) = Iterators.filter(_ -> true, idmap(x)) # Size unknown.

@testset "Input conversions." begin

    #---------------------------------------------------------------------------------------
    # To scalar names.

    input = 'a'
    res = convert(Symbol, input) # Test this form once..
    @test same_type_value(res, :a)

    # To scalar symbol.
    @test conv(Symbol, "a" => :a, 'a' => :a, :a => Alias)

    # To scalar strings.
    @test conv(String, 'a' => "a", :a => "a", "a" => Alias)

    #---------------------------------------------------------------------------------------
    # To floating point values, any collection.

    @test conv(Float64, 5 => 5.0)
    @test conv(Vector{Float64}, [5, 8] => [5.0, 8.0])
    @test conv(Vector{Float64}, idmap([5, 8]) => [5.0, 8.0])
    @test conv(Vector{Float64}, filt([5, 8]) => [5.0, 8.0])
    @test conv(SparseVector{Float64}, [5, 8] => sparse([5.0, 8.0]))
    @test conv(SparseVector{Float64}, idmap([5, 8]) => sparse([5.0, 8.0]))
    @test conv(Matrix{Float64}, [5 8; 8 5] => [5.0 8.0; 8.0 5.0])
    @test conv(SparseMatrix{Float64}, [5 8; 8 5] => sparse([5.0 8.0; 8.0 5.0]))

    # Aliased version if exact type is provided.
    @test conv(Float64, 5.0 => Alias)
    @test conv(Vector{Float64}, [5.0, 8.0] => Alias)
    @test conv(SparseVector{Float64}, sparse([5.0, 8.0]) => Alias)
    @test conv(Matrix{Float64}, [5.0 8.0; 8.0 5.0] => Alias)
    @test conv(SparseMatrix{Float64}, sparse([5.0 8.0; 8.0 5.0]) => Alias)

    #---------------------------------------------------------------------------------------
    # To integers, any collection.

    @test conv(Int, 0x5 => 5)
    @test conv(Int, 0xffffffff => 4294967295)
    @test conv(SparseVector{Int}, [5, 8] => sparse([5, 8]))
    @test conv(SparseMatrix{Int}, [5 8; 8 5] => sparse([5 8; 8 5]))

    # Aliased version if exact type is provided.
    @test conv(Int, 5 => Alias)
    @test conv(Vector{Int}, [5, 8] => Alias)
    @test conv(SparseVector{Int}, sparse([5, 8]) => Alias)
    @test conv(Matrix{Int}, [5 8; 8 5] => Alias)
    @test conv(SparseMatrix{Int}, sparse([5 8; 8 5]) => Alias)

    #---------------------------------------------------------------------------------------
    # To booleans, any collection.

    @test conv(Bool, 1 => true)
    @test conv(Bool, 0x1 => true)

    v = [true, false]
    @test conv(Vector{Bool}, [1, 0] => v)
    @test conv(Vector{Bool}, idmap([1, 0]) => v)
    @test conv(Vector{Bool}, filt([1, 0]) => v)
    @test conv(Vector{Bool}, BitVector([1, 0]) => v)
    @test conv(Vector{Bool}, v => Alias)
    s = sparse(v)
    @test conv(SparseVector{Bool}, [1, 0] => s)
    @test conv(SparseVector{Bool}, idmap([1, 0]) => s)
    @test conv(SparseVector{Bool}, BitVector([1, 0]) => s)
    @test conv(SparseVector{Bool}, s => Alias)

    m = [true; false;; false; true]
    @test conv(Matrix{Bool}, [1; 0;; 0; 1] => m)
    @test conv(Matrix{Bool}, BitMatrix([1; 0;; 0; 1]) => m)
    @test conv(Matrix{Bool}, m => Alias)
    s = sparse(m)
    @test conv(SparseMatrix{Bool}, [1; 0;; 0; 1] => s)
    @test conv(SparseMatrix{Bool}, BitMatrix([1; 0;; 0; 1]) => s)
    @test conv(SparseMatrix{Bool}, s => Alias)
    # etc.

    #---------------------------------------------------------------------------------------
    # Conversion failures.

    input = [0, 1, 2]
    @convfails(convert(Vector{Bool}, input),
        Bool, 2, (:u, (3,)), "(detail down the stacktrace)")

    @test_err(convert(Vector{Bool}, input),
        """
        In the provided input at [3]:
        Cannot convert to `$Bool`:
        (detail down the stacktrace)
        Received: 2  ::$Int\
        """)

    @convfails(convert(Vector{Bool}, Type),
        Vector{Bool}, Type, :uwhole, "Input is not iterable.")
    @convfails(convert(Matrix{Bool}, idmap(1:3)),
        Matrix{Bool}, idmap(1:3), :uwhole, "Input is not iterable as an array.")
    @convfails(convert(SparseMatrix{Bool}, idmap(1:3)),
        SparseMatrix{Bool}, idmap(1:3), :uwhole, "Input is not iterable as an array.")

    @test_err(convert(Vector{Bool}, Type),
        """
        Cannot convert to `Vector{Bool}`:
        Input is not iterable.
        Received: $Type  ::$UnionAll\
        """)

    # Reject key-values pairs where information would be lost.
    keynot(T) = "Would not convert $T to an array: keys would be lost."
    input = (; a = 5, b = 8)
    @convfails(convert(Vector{Int}, input), Vector{Int}, input, :uwhole, keynot(NamedTuple))
    input = Dict([:a => 5, :b => 8])
    @convfails(convert(Vector{Int}, input),
        Vector{Int}, input, :uwhole, keynot(AbstractDict))
    input = OrderedDict(input)
    @convfails(convert(Vector{Int}, input),
        Vector{Int}, input, :uwhole, keynot(AbstractDict))

    # Reject trans-dimension conversions.
    dimnot = "Would not convert vector to matrix, vice-versa or etc."
    @convfails(convert(Vector{Bool}, Bool[0 1; 1 0]),
        Vector{Bool}, Bool[0 1; 1 0], :uwhole, dimnot)
    @convfails(convert(Matrix{Bool}, Bool[0, 1, 1, 0]),
        Matrix{Bool}, Bool[0, 1, 1, 0], :uwhole, dimnot)
    @convfails(convert(SparseMatrix{Bool}, Bool[0, 1, 1, 0]),
        SparseMatrix{Bool}, Bool[0, 1, 1, 0], :uwhole, dimnot)

    # Sparse arrays don't accept unclear 'zero' conversions.
    @test conv(Vector{Symbol}, ["a", "b"] => [:a, :b])
    @convfails(convert(SparseVector{Symbol}, ["a", "b"]),
        SparseVector{Symbol}, ["a", "b"], :uwhole,
        "Would not convert to a sparse structure \
         when the element type (Symbol) has no null/zero value.")

    @test conv(SparseVector{Float64}, idmap(1:3) => sparse(Float64[1, 2, 3]))
    @convfails(convert(SparseVector{Float64}, filt(1:3)),
        SparseVector{Float64}, filt(1:3), :uwhole,
        "Would not convert to a sparse structure when the input has no `size`.")

    @convfails(convert(SparseVector{Float64}, [1, :x, 3]),
        SparseVector{Float64}, :x, (:u, (2,)), "Element cannot be compared to null/zero.")

    #---------------------------------------------------------------------------------------
    # Try several conversions at once, first match first served.
    id = identity

    input = 4
    res = try_convert(input, Symbol => id, Float64 => sqrt, Int => abs)
    @test same_type_value(res, 2.0)

    input = 5
    @checkfails(try_convert(input, Symbol => id, Vector{String} => id),
        nothing, 5, :uwhole,
        """
        Cannot convert input to either:
          - $Symbol
          - $(Vector{String})
        (see attempts down the stacktrace)\
        """)

end

end

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
    @test conv(SparseVector{Float64}, [5, 8] => sparse([5.0, 8.0]))
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
    @test conv(Vector{Bool}, BitVector([1, 0]) => v)
    @test conv(Vector{Bool}, v => Alias)
    s = sparse(v)
    @test conv(SparseVector{Bool}, [1, 0] => s)
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
    # To ref-value maps, any iterable of pairs.

    # Index refs.
    @test conv(Map{Float64}, [1 => 5, (2, 8)] => OrderedDict(1 => 5.0, 2 => 8.0))

    # Label refs.
    @test conv(
        Map{Float64},
        ["a" => 5, (:b, 8), ['c', 13]] => OrderedDict(:a => 5.0, :b => 8.0, :c => 13.0),
    )

    # Default to symbol index.
    @test conv(Map{Float64}, [] => OrderedDict{Symbol,Float64}())

    # Group refs.
    @test conv(
        Map{Float64},
        (
            [("a", :b) => 5, [(:c, 'd'), 8], [:e, 13]],
            OrderedDict(:a => 5.0, :b => 5.0, :c => 8.0, :d => 8.0, :e => 13.0),
        ),
    )
    @test conv(
        Map{Float64},
        (
            [(1, 2) => 5, [(3, 4), 8], [5, 13]],
            OrderedDict(1 => 5.0, 2 => 5.0, 3 => 8.0, 4 => 8.0, 5 => 13.0),
        ),
    )

    # Alias by using the exact same type.
    @test conv(Map{Float64}, OrderedDict(1 => 5.0, 2 => 8.0) => Alias)
    @test conv(Map{Float64}, OrderedDict(:a => 5.0, :b => 8.0) => Alias)

    # Special binary case.
    @test conv(
        BinMap,
        [1, 2] => OrderedSet([1, 2]),
        ["a", :b, 'c'] => OrderedSet([:a, :b, :c]),
        [] => OrderedSet{Symbol}(),
        OrderedSet([:a, :b, :c]) => Alias,
        # Accept boolean masks.
        Bool[1, 0, 1, 1, 0] => OrderedSet([1, 3, 4]),
        sparse(Bool[1, 0, 1, 1, 0]) => OrderedSet([1, 3, 4]),
    )

    # Still, use Bool as expected for ternary true/false/miss logic.
    @test conv(Map{Bool}, [1 => true, 3 => false] => OrderedDict([1 => true, 3 => false]))

    # Use boolean mask as grouped refs.
    @test conv(
        Map{Float64},
        (
            [Bool[1, 0, 1, 0, 0] => 5, (sparse(Bool[0, 1, 0, 1, 0]), 8), [5, 13]],
            OrderedDict(1 => 5.0, 2 => 8.0, 3 => 5.0, 4 => 8.0, 5 => 13.0),
        ),
    )

    #---------------------------------------------------------------------------------------
    # To adjacency lists, any nested iterable.

    @test conv(
        Adjacency{Float64},
        (
            [1 => [5 => 50, 6 => 60], (2, (7 => 14, 8 => 16))],
            OrderedDict(
                1 => OrderedDict(5 => 50.0, 6 => 60.0),
                2 => OrderedDict(7 => 14.0, 8 => 16.0),
            ),
        ),
    )

    @test conv(
        Adjacency{Float64},
        (
            ["a" => [:b => 50, 'c' => 60], ("b", (:c => 14, 'a' => 16))],
            OrderedDict(
                :a => OrderedDict(:b => 50.0, :c => 60.0),
                :b => OrderedDict(:c => 14.0, :a => 16.0),
            ),
        ),
    )

    # Grouping refs and values on either source or target side.
    @test conv(
        Adjacency{Float64},
        (
            [
                # Group source refs.
                ("a", :b) => [:c => 5, ['d', 6]],
                # Specify values per-source.
                [(:a => 7, ('b', 8)), [:e, 'f']],
                # Group even more within either lhs..
                (((['a', :b], 9), 'c' => 10), [:g :h]),
                # .. or lhs.
                ('a', :b, "c") => [(:i, 'j') => 11, (:k, 12)],
            ],
            #! format: off
            OrderedDict(
                :a => OrderedDict(
                    :c => 5.0,
                    :d => 6.0,
                    :e => 7.0,
                    :f => 7.0,
                    :g => 9.0,
                    :h => 9.0,
                    :i => 11.0,
                    :j => 11.0,
                    :k => 12.0,
                ),
                :b => OrderedDict(
                    :c => 5.0,
                    :d => 6.0,
                    :e => 8.0,
                    :f => 8.0,
                    :g => 9.0,
                    :h => 9.0,
                    :i => 11.0,
                    :j => 11.0,
                    :k => 12.0,
                ),
                :c => OrderedDict(
                    :g => 10.0,
                    :h => 10.0,
                    :i => 11.0,
                    :j => 11.0,
                    :k => 12.0,
                ),
            ),
            #! format: on
        ),
    )

    # Same with indices and boolean masks.
    @test conv(
        Adjacency{Float64},
        (
            [
                Bool[1, 1, 0] => [3 => 50, [4, 60]],
                [(1 => 70, (2, 80)), sparse(Bool[0, 0, 0, 0, 1, 1])],
                ((([1, 2], 90), 3 => 100), Bool[0, 0, 0, 0, 0, 0, 1, 1]),
                Bool[1, 1, 1] => [(9, 10) => 110, (11, 120)],
            ],
            #! format: off
            OrderedDict(
                1 => OrderedDict(
                    3  => 50.0,
                    4  => 60.0,
                    5  => 70.0,
                    6  => 70.0,
                    7  => 90.0,
                    8  => 90.0,
                    9  => 110.0,
                    10 => 110.0,
                    11 => 120.0,
                ),
                2 => OrderedDict(
                    3  => 50.0,
                    4  => 60.0,
                    5  => 80.0,
                    6  => 80.0,
                    7  => 90.0,
                    8  => 90.0,
                    9  => 110.0,
                    10 => 110.0,
                    11 => 120.0,
                ),
                3 => OrderedDict(
                    7  => 100.0,
                    8  => 100.0,
                    9  => 110.0,
                    10 => 110.0,
                    11 => 120.0,
                ),
            ),
            #! format: on
        ),
    )

    @test conv(Adjacency{Float64}, [] => OrderedDict{Symbol,OrderedDict{Symbol,Float64}}())

    @test conv(
        Adjacency{Float64},
        OrderedDict(
            :a => OrderedDict(:b => 50.0, :c => 60.0),
            :b => OrderedDict(:c => 14.0, :a => 16.0),
        ) => Alias,
    )

    # Special binary case.
    @test conv(
        BinAdjacency,
        (
            [1 => [5, 6], (2, (7, 8))],
            OrderedDict(1 => OrderedSet([5, 6]), 2 => OrderedSet([7, 8])),
        ),
        (
            ["a" => [:b, 'c'], ("b", (:c, 'a'))],
            OrderedDict(:a => OrderedSet([:b, :c]), :b => OrderedSet([:c, :a])),
        ),
        (
            [(1, 2) => [3], ((2, 3), 1)],
            OrderedDict(
                1 => OrderedSet([3]),
                2 => OrderedSet([3, 1]),
                3 => OrderedSet([1]),
            ),
        ),
        (
            [("a", :b) => ['c'], (("b", :c), 'a')],
            OrderedDict(
                :a => OrderedSet([:c]),
                :b => OrderedSet([:c, :a]),
                :c => OrderedSet([:a]),
            ),
        ),
        (
            ["a" => :b, ("b", 'c')], # Allow singleton refs.
            OrderedDict(:a => OrderedSet([:b]), :b => OrderedSet([:c])),
        ),
        [] => OrderedDict{Symbol,OrderedSet{Symbol}}(),
        OrderedDict(1 => OrderedSet([2, 7]), 2 => OrderedSet([3, 8])) => Alias,

        # Accept boolean matrices.
        (
            Bool[
                0 1 0
                0 0 0
                1 0 1
            ],
            OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])),
        ),
        (
            sparse(Bool[
                0 1 0
                0 0 0
                1 0 1
            ]),
            OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])),
        ),
    )

    # Ternary logic.
    @test conv(
        Adjacency{Bool},
        (
            [1 => [5 => true, 7 => false], (2, ([7, false], 9 => true))],
            OrderedDict(
                1 => OrderedDict(5 => true, 7 => false),
                2 => OrderedDict(7 => false, 9 => true),
            ),
        ),
    )

    #---------------------------------------------------------------------------------------
    # Exposed conversion failures.

    input = [0, 1, 2]
    @convfails(convert(Vector{Bool}, input),
        Bool, 2, (3,), "(detail down the stacktrace)")

    @test_err(convert(Vector{Bool}, input),
        """
        In the provided input at [3]:
        Cannot convert to `$Bool`:
        (detail down the stacktrace)
        Received: 2  ::$Int\
        """)

    @convfails(convert(Vector{Bool}, Type),
        Vector{Bool}, Type, :whole, "Input is not iterable.")
    @test_err(convert(Vector{Bool}, Type),
        """
        Cannot convert to `Vector{Bool}`:
        Input is not iterable.
        Received: $Type  ::$UnionAll\
        """)

    # Sparse arrays don't accept unclear 'zero' conversions.
    @test conv(Vector{Symbol}, ["a", "b"] => [:a, :b])
    @convfails(convert(SparseVector{Symbol}, ["a", "b"]),
        SparseVector{Symbol}, ["a", "b"], :whole, "Conversion not implemented.")

    #---------------------------------------------------------------------------------------
    # Try several conversions at once, first match first served.
    id = identity

    input = 4
    res = try_convert(input, Symbol => id, Float64 => sqrt, Int => abs)
    @test same_type_value(res, 2.0)

    input = 5
    @checkfails(try_convert(input, Symbol => id, Vector{String} => id),
        nothing, 5, :whole, nothing,
        """
        Cannot convert input to either:
          - $Symbol
          - $(Vector{String})
        (see attempts down the stacktrace)\
        """)

end

end

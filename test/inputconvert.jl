module InputConvertTest

using EcologicalNetworksDynamics:
    inputconvert, input_try, SparseMatrix, Map, Adjacency, BinMap, BinAdjacency

using Main: @inputfails

using Test
using SparseArrays
using OrderedCollections

struct _Alias end
Alias = _Alias() # Use as an unambiguous keyword.

@testset "Graph data conversion." begin

    # ======================================================================================
    # Check convenience macro type conversion.

    same_type_value(a, b) = a isa typeof(b) && a == b
    aliased(a, b) = a === b

    #---------------------------------------------------------------------------------------
    # To scalar names.

    input = 'a'
    res = inputconvert(Symbol, input) # Test this form once..
    @test same_type_value(res, :a)

    # .. then shorten subsequent tests.
    function conv(T, pairs...)
        for (input, expected) in pairs
            actual = inputconvert(T, input)
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
    @test conv(Vector{Bool}, [1, 0] => [true, false])
    @test conv(Vector{Bool}, [false, true] => Alias)
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
    # Try several conversions at once, first match first served.
    id = identity

    input = 4
    res = input_try(input, Symbol => id, Float64 => sqrt, Int => abs)
    @test same_type_value(res, 2.0)

    # ======================================================================================
    # Exposed conversion failures.

    input = 5
    @inputfails(
        (input_try(input, Symbol => id, Vector{Float64} => id)),
        "Cannot convert input to either:\n  \
         - $Symbol\n  \
         - $(Vector{Float64})\n\
         Received value: 5 ::$Int.",
    )

    input = [0, 1, 2]
    @inputfails(
        (inputconvert(Vector{Bool}, input)),
        "Error when attempting to convert input (detail down the stacktrace):\n\
         Target type was $(Vector{Bool}).\n\
         Input was: [0, 1, 2] ::$(Vector{Int})",
    )

    #---------------------------------------------------------------------------------------
    # More specific failures.

    # (don't check first error in stacktrace)
    cv(type, input) = inputconvert(type, input)
    cv(type, input, ExpectedRefType) = inputconvert(type, input; ExpectedRefType)

    # Binary maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @inputfails( #  :not_iterable
        cv(BinMap, Type),
        "Input for binary map needs to be iterable.\n\
         Received: Type ::UnionAll."
    )

    @inputfails( #  :pair_as_iterable
        cv(BinMap, :a => :b),
        "The pair at [] is just considered an iterable in this context, \
         which may be confusing. \
         Consider using an explicit vector instead like [:a, :b]."
    )

    @inputfails( #  :not_a_ref
        cv(BinMap, [Type]),
        "Cannot interpret node reference as integer index or symbol label: \
         received at [1]: Type ::UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type
        cv(BinMap, [5], Symbol),
        "Invalid node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1]: 5 ::$Int."
    )

    @inputfails( #  :unexpected_ref_type
        cv(BinMap, [:label], Int),
        "Invalid node reference type. \
         Expected $Int (or convertible). \
         Received instead at [1]: :label ::Symbol."
    )

    @inputfails( #  :inconsistent_ref_type
        cv(BinMap, [5, :a]),
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found at [2]: :a ::Symbol.",
    )

    # :duplicate_node
    @inputfails(cv(BinMap, [5, 5]), "Duplicated node reference at [2]: 5 ::$Int.")

    # (from boolean masks)
    @inputfails( # :boolean_label
        cv(BinMap, Bool[0, 0, 1, 0, 1], Symbol),
        "A label-indexed binary map cannot be produced from boolean vectors."
    )

    # :unexpected_ref_type for boolean masks is tested when used for parsing grouped refs.

    # Maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    M = Map{Float64}

    @inputfails( #  :not_iterable
        cv(M, Type),
        "Input for map needs to be iterable.\nReceived: Type ::UnionAll.",
    )

    #  :not_a_pair
    @inputfails(cv(M, [5]), "Not a 'reference(s) => value' pair at [1]: 5 ::$Int.")
    @inputfails(cv(M, "abc"), "Not a 'reference(s) => value' pair at [1]: 'a' ::Char.")

    @inputfails( #  :not_a_ref (plain)
        cv(M, [(Type, "a")]),
        "Cannot interpret node reference as integer index or symbol label: \
         received at [1][left]: Type ::UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type (plain)
        cv(M, [(5, "a")], Symbol),
        "Invalid node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1][left]: 5 ::$Int.",
    )

    @inputfails( #  :unexpected_ref_type (plain)
        cv(M, [(:label, "a")], Int),
        "Invalid node reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][left]: :label ::Symbol.",
    )

    @inputfails( #  :inconsistent_ref_type (plain)
        cv(M, [(5, 8), (:a, 5)]),
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found at [2][left]: :a ::Symbol."
    )

    @inputfails( #  :inconsistent_ref_type (plain)
        cv(M, [(:a, 5), (8, 5)]),
        "The node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found at [2][left]: 8 ::$Int."
    )

    @inputfails( #  :not_a_ref (grouped)
        cv(M, [[:a, Type] => 5]),
        "Cannot interpret node reference as integer index or symbol label: \
         received at [1][left][2]: Type ::UnionAll."
    )

    @inputfails( #  :unexpected_ref_type (grouped)
        cv(M, [[5, :b] => 8], Symbol),
        "Invalid node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1][left][1]: 5 ::$Int."
    )

    @inputfails( #  :inconsistent_ref_type (grouped)
        cv(M, [:a => 5, [:b, 3] => 8]),
        "The node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found at [2][left][2]: 3 ::$Int."
    )

    @inputfails( #  :duplicate_node (grouped)
        cv(M, [[:a, :b, :a] => 5]),
        "Duplicated node reference at [1][left][3]: :a ::Symbol."
    )

    @inputfails( #  :boolean_label
        cv(M, [:a => 5, Bool[0, 1, 1] => 8], Symbol),
        "A label-indexed group of nodes \
         cannot be produced from boolean vectors \
         at [2][left]: Bool[0, 1, 1] ::Vector{Bool}."
    )

    @inputfails( #  :inconsistent_ref_type (bool)
        cv(M, [:a => 5, Bool[0, 1, 1] => 8]),
        "The group of nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) \
         is now found at [2][left]: Bool[0, 1, 1] ::Vector{Bool}."
    )

    @inputfails( #  :not_a_value
        cv(M, [(5, "a")]),
        "Expected values of type 'Float64', \
         received instead at [1][right]: \"a\" ::String.",
    )

    @inputfails( #  :duplicate_node
        cv(M, [[:a, :b] => 5, [:c, :a] => 8]),
        "Duplicated node reference :\n\
         Received before: a => 5.0\n\
         Received now   : a => 8 ::$Int at [2][left][2]: :a ::Symbol."
    )

    # Binary adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    @inputfails( #  :not_iterable
        cv(BinAdjacency, Type),
        "Input for binary adjacency map needs to be iterable.\n\
         Received: Type ::UnionAll.",
    )

    @inputfails( #  :not_a_pair
        cv(BinAdjacency, [Type]),
        "Not a 'source(s) => target(s)' pair at [1]: Type ::UnionAll.",
    )

    @inputfails( #  :not_a_ref (plain source)
        cv(BinAdjacency, [Type => 5]),
        "Cannot interpret source node reference as integer index or symbol label: \
         received at [1][left]: Type ::UnionAll.",
    )

    @inputfails( #  :not_a_ref (plain target)
        cv(BinAdjacency, [5 => Type]),
        "Cannot interpret target node reference as integer index or symbol label: \
         received at [1][right]: Type ::UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type (plain source)
        cv(BinAdjacency, [:a => :b], Int),
        "Invalid source node reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][left]: :a ::Symbol.",
    )

    @inputfails( #  :unexpected_ref_type (plain target)
        cv(BinAdjacency, [1 => 2], Symbol),
        "Invalid source node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1][left]: 1 ::$Int.",
    )

    @inputfails( #  :inconsistent_ref_type (plain source)
        cv(BinAdjacency, [:a => :b, 2 => :c]),
        "The source node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found at [2][left]: 2 ::$Int.",
    )

    @inputfails( #  :inconsistent_ref_type (plain target)
        cv(BinAdjacency, [1 => :b]),
        "The target node reference type for this input \
         was first inferred to be an index ($Int) based on the received '1', \
         but a label (Symbol) is now found at [1][right]: :b ::Symbol.",
    )

    @inputfails( #  :not_a_ref (grouped sources)
        cv(BinAdjacency, [2 => 5, [1, Type] => 3]),
        "Cannot interpret source node reference as integer index or symbol label: \
         received at [2][left][2]: Type ::UnionAll.",
    )

    @inputfails( #  :not_a_ref (grouped targets)
        cv(BinAdjacency, [2 => 5, 1 => [3, Type]]),
        "Cannot interpret target node reference as integer index or symbol label: \
         received at [2][right][2]: Type ::UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type (grouped sources)
        cv(BinAdjacency, [[:a] => 5], Int),
        "Invalid source node reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][left][1]: :a ::Symbol.",
    )

    @inputfails( #  :unexpected_ref_type (grouped targets)
        cv(BinAdjacency, [:a => [:b, :c, 4]], Symbol),
        "Invalid target node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1][right][3]: 4 ::$Int.",
    )

    @inputfails( #   :pair_as_iterable (grouped sources)
        cv(BinAdjacency, [(:a => :b) => :c], Symbol),
        "The pair at [1][left] is just considered an iterable in this context, \
         which may be confusing. \
         Consider using an explicit vector instead like [:a, :b].",
    )

    @inputfails( #   :pair_as_iterable (grouped targets)
        cv(BinAdjacency, [:a => :b => :c], Symbol),
        "The pair at [1][right] is just considered an iterable in this context, \
         which may be confusing. \
         Consider using an explicit vector instead like [:b, :c].",
    )

    @inputfails( #  :inconsistent_ref_type (grouped sources)
        cv(BinAdjacency, [[1, :b, 3] => 4]),
        "The source node reference type for this input \
         was first inferred to be an index ($Int) based on the received '1', \
         but a label (Symbol) is now found at [1][left][2]: :b ::Symbol.",
    )

    @inputfails( #  :inconsistent_ref_type (grouped targets)
        cv(BinAdjacency, [:a => [:b, :c, 4]]),
        "The target node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found at [1][right][3]: 4 ::$Int.",
    )

    @inputfails( #  :duplicate_node (grouped sources)
        cv(BinAdjacency, [:a => :b, :a => :c, [:b, :c, 'b'] => :a]),
        "Duplicated source node reference at [3][left][3]: 'b' ::Char.",
    )

    @inputfails( #  :boolean_label (sources)
        cv(BinAdjacency, [:a => :b, Bool[1, 1, 0] => :c], Symbol),
        "A label-indexed group of source nodes cannot be produced from boolean vectors \
         at [2][left]: Bool[1, 1, 0] ::Vector{Bool}.",
    )

    @inputfails( #  :boolean_label (targets)
        cv(BinAdjacency, [:a => :b, :c => Bool[1, 1, 0]], Symbol),
        "A label-indexed group of target nodes cannot be produced from boolean vectors \
         at [2][right]: Bool[1, 1, 0] ::Vector{Bool}.",
    )

    @inputfails( #  :inconsistent_ref_type (bool sources)
        cv(BinAdjacency, [:a => :b, Bool[1, 1, 0] => :c]),
        "The group of source nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found \
         at [2][left]: Bool[1, 1, 0] ::Vector{Bool}.",
    )

    @inputfails( #  :inconsistent_ref_type (bool targets)
        cv(BinAdjacency, [:a => :b, :c => Bool[1, 1, 0]]),
        "The group of target nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found \
         at [2][right]: Bool[1, 1, 0] ::Vector{Bool}.",
    )

    @inputfails( #  :duplicate_edge
        cv(BinAdjacency, [5 => [8], 4 + 1 => [4 * 2]]),
        "Duplicate edge specification 5 → 8 at [2][right][1]: 8 ::$Int."
    )

    @inputfails( #  :duplicate_edge
        cv(BinAdjacency, [[:a, :b] => [:b], :a => [:c, :b]]),
        "Duplicate edge specification :a → :b at [2][right][2]: :b ::Symbol."
    )

    @inputfails( #  :no_targets
        cv(BinAdjacency, [[1, 2] => []]),
        "No target provided for source 1 at [1][right]."
    )

    @inputfails( #  :no_targets
        cv(BinAdjacency, [:a => [:b], :c => ()]),
        "No target provided for source :c at [2][right]."
    )

    @inputfails( #  :no_sources
        cv(BinAdjacency, [[] => [1, 2]]),
        "No sources provided at [1][left].",
    )

    @inputfails( #  :boolean_label
        cv(BinAdjacency, Bool[1 0 1], Symbol),
        "A label-indexed binary adjacency list cannot be produced from boolean matrices.",
    )

    # Adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    A = Adjacency{Float64}

    @inputfails( #  :not_iterable
        cv(A, Type),
        "Input for adjacency map needs to be iterable.\n\
         Received: Type ::UnionAll.",
    )

    @inputfails( #  :not_a_pair
        cv(A, [Type]),
        "Not a 'source(s) => target(s)' pair at [1]: Type ::UnionAll.",
    )


    @inputfails( #  :not_a_pair (plain sources) : pick :not_a_ref
        cv(A, [Type => 5]),
        "Cannot interpret source reference as integer index or symbol label: \
         received at [1][left]: $Type ::$UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type (plain source)
        cv(A, [:a => 5], Int),
        "Invalid source reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][left]: :a ::Symbol.",
    )

    @inputfails( # :inconsistent_ref_type (plain source)
        cv(A, [(:a => 5) => :b, (1 => 8) => :c]),
        "The source reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but an index ($Int) is now found at [2][left][left]: 1 ::$Int.",
    )

    @inputfails( # :not_a_value (plain source)
        cv(A, [(:a => 5im) => :b]),
        "Expected values of type '$Float64', \
         received instead at [1][left][right]: 0 + 5im ::$Complex{$Int}.",
    )

    @inputfails( # :not_a_pair (map source) : pick :not_a_ref
        cv(A, [[Type] => 5]),
        "Cannot interpret source reference as integer index or symbol label: \
         received at [1][left][1]: $Type ::$UnionAll.",
    )

    @inputfails( # :unexpected_ref_type (map source)
        cv(A, [[5] => 8], Symbol),
        "Invalid source reference type. \
         Expected $Symbol (or convertible). \
         Received instead at [1][left][1]: 5 ::$Int.",
    )

    @inputfails( # :inconsistent_ref_type (map source)
        cv(A, [[5, :a] => 8]),
        "The source reference type for this input \
         was first inferred to be an index ($Int) \
         based on the received '5', \
         but a label ($Symbol) is now found at [1][left][2]: :a ::$Symbol.",
    )

    @inputfails( # :duplicate_node (map source)
        cv(A, [[:a => 5, :a => 8] => :b]),
        "Duplicated source reference :\n\
         Received before: a => 5.0\n\
         Received now   : a => 8 ::$Int at [1][left][2][left][1]: :a ::$Symbol.",
    )

    @inputfails( # :duplicate_node (map source)
        cv(A, [[:a => 5, [:b, :b] => 8] => :c]),
        "Duplicated source reference at [1][left][2][left][2]: :b ::$Symbol.",
    )

    @inputfails( # :duplicate_node (map source)
        cv(A, [[:a, :a] => 8]),
        "Duplicated source reference at [1][left][2]: :a ::$Symbol.",
    )

    @inputfails( # :boolean_label (map source)
        cv(A, [Bool[0, 1, 1, 0] => (2 => 10)], Symbol),
        "A label-indexed group of sources cannot be produced from boolean vectors \
         at [1][left]: $Bool[0, 1, 1, 0] ::$Vector{$Bool}.",
    )

    @inputfails( # :inconsistent_ref_type (map source)
        cv(A, [:a => (:b => 5), Bool[0, 1, 1, 0] => (2 => 10)]),
        "The group of sources reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) \
         is now found at [2][left]: $Bool[0, 1, 1, 0] ::$Vector{$Bool}.",
    )

    @inputfails( # :not_a_value (plain source)
        cv(A, [[:a => 5im] => :b]),
        "Expected values of type '$Float64', \
         received instead at [1][left][1][right]: 0 + 5im ::$Complex{$Int}.",
    )

    # TODO: better explain that the duplication comes from the boolean?
    # (although this really is a weird input)
    @inputfails( # :duplicate_node (map source)
        cv(A, [[1 => 5, 2 => 8, Bool[0, 1, 1] => 9] => 3]),
        "Duplicated source reference :\n\
         Received before: 2 => 8.0\n\
         Received now   : 2 => 9 ::$Int at [1][left][3][left][1]: 2 ::$Int.",
    )

    # # # ≈ same on the target side # # #
    # TODO: I am having a hard time making sure that all error paths are covered.
    # Design a more systematic way?

    @inputfails( #  :not_a_pair (plain targets) : pick :not_a_ref
        cv(A, [5 => Type]),
        "Cannot interpret target reference as integer index or symbol label: \
         received at [1][right]: $Type ::$UnionAll.",
    )

    @inputfails( #  :unexpected_ref_type (plain target)
        cv(A, [1 => (:a => 5)], Int),
        "Invalid target reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][right][left]: :a ::Symbol.",
    )

    @inputfails( # :inconsistent_ref_type (plain target)
        cv(A, [:a => (:b => 5), :c => (3 => 8)]),
        "The target reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but an index ($Int) is now found at [2][right][left]: 3 ::$Int.",
    )

    @inputfails( # :not_a_value (plain target)
        cv(A, [:a => (:b => 5im)]),
        "Expected values of type '$Float64', \
         received instead at [1][right][right]: 0 + 5im ::$Complex{$Int}.",
    )

    @inputfails( # :not_a_pair (map target) : pick :not_a_ref
        cv(A, [5 => [Type]]),
        "Cannot interpret target reference as integer index or symbol label: \
         received at [1][right][1]: $Type ::$UnionAll.",
    )

    @inputfails( # :unexpected_ref_type (map target)
        cv(A, [:a => [2]], Symbol),
        "Invalid target reference type. \
         Expected $Symbol (or convertible). \
         Received instead at [1][right][1]: 2 ::$Int.",
    )

    @inputfails( # :duplicate_node (map target)
        cv(A, [:a => [:b => 5, :b => 8]]),
        "Duplicated target reference :\n\
         Received before: b => 5.0\n\
         Received now   : b => 8 ::$Int at [1][right][2][left][1]: :b ::$Symbol.",
    )

    @inputfails( # :duplicate_node (map target)
        cv(A, [:a => [:b => 5, [:c, :c] => 8]]),
        "Duplicated target reference at [1][right][2][left][2]: :c ::$Symbol.",
    )

    @inputfails( # :not_a_value (plain target)
        cv(A, [:a => [:b => 5im]]),
        "Expected values of type '$Float64', \
         received instead at [1][right][1][right]: 0 + 5im ::$Complex{$Int}.",
    )

    # # # Specific to Adjacency maps # # #

    @inputfails( # :two_values
        cv(A, [(:a => 5) => [:b => 8]]),
        "Cannot associate values to both source and target ends of edges at [1]:\n\
         Received LHS: ((:a, 5.0),)\n\
         Received RHS: $OrderedDict(:b => 8.0).",
    )

    @inputfails( # :no_value
        cv(A, [:a => [:b, :c]]),
        "No values found for either source or target end of edges at [1]:\n\
         Received LHS: (:a,)\n\
         Received RHS: $OrderedSet{$Symbol}([:b, :c])."
    )

    @inputfails( # :duplicate_edge
        cv(A, [:a => [:b => 5, :c => 8], [:a => 13] => [:c, :d]]),
        "Duplicate edge specification:\n\
         Previously received: :a → :c (8.0)\n\
         Now received:        :a → :c (13.0) at [2][right][1]: :c ::$Symbol."
    )

    @inputfails( # :no_targets
        cv(A, [:a => []]),
        "No target provided for `target => value` pair at [1][left][1].",
    )

    @inputfails( # :no_sources
        cv(A, [[] => :b]),
        "No sources provided at [1][left][0].",
    )

end

end

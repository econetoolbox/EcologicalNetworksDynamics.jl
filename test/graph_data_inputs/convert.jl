struct _Alias end

@testset "Graph data conversion." begin

    # ======================================================================================
    # Check convenience macro type conversion.

    same_type_value(a, b) = a isa typeof(b) && a == b
    aliased(a, b) = a === b

    #---------------------------------------------------------------------------------------
    # To scalar symbols.

    input = 'a'
    res = @tographdata input YSV{Float64} # Test this form once..
    @test same_type_value(res, :a)

    # .. then shorten subsequent tests.
    Alias = _Alias()
    function convert(types, input, expected)
        # (reproduce @tographdata macro)
        types = GraphDataInputs.graph_data_list(types, nothing; escape = false)
        types = Base.eval.((GraphDataInputs,), types)
        actual = GraphDataInputs._tographdata(:input, input, types)
        match = if expected isa _Alias
            aliased(input, actual)
        else
            same_type_value(expected, actual)
        end
        if !match
            println("expected: $expected ::$(typeof(expected))")
            println("actual  : $actual ::$(typeof(actual))")
        end
        match
    end

    @test convert(:(YSV{Float64}), "a", :a)
    @test convert(:(Y{}), "a", :a)

    # To scalar strings.
    @test convert(:(SYV{String}), 'a', "a")
    @test convert(:(SYV{String}), :a, "a")

    # (type order matters or the first matching wins)
    @test convert(:(YSV{String}), 'a', :a) # (Y first wins)

    #---------------------------------------------------------------------------------------
    # To floating point values, any collection.

    @test convert(:(YSV{Float64}), 5, 5.0)
    @test convert(:(YSV{Float64}), [5], [5.0])
    @test convert(:(YSN{Float64}), [5, 8], sparse([5.0, 8.0]))
    @test convert(:(YSM{Float64}), [5 8; 8 5], [5.0 8.0; 8.0 5.0])
    @test convert(:(YSE{Float64}), [5 8; 8 5], sparse([5.0 8.0; 8.0 5.0]))

    # Aliased version if exact type is provided.
    @test convert(:(YSV{Float64}), 5.0, 5.0)
    @test convert(:(YSV{Float64}), [5.0], Alias) # No conversion has been made.
    @test convert(:(YSN{Float64}), sparse([5.0, 8.0]), Alias)
    @test convert(:(YSM{Float64}), [5.0 8.0; 8.0 5.0], Alias)
    @test convert(:(YSE{Float64}), sparse([5.0 8.0; 8.0 5.0]), Alias)

    #---------------------------------------------------------------------------------------
    # To integers, any collection.

    @test convert(:(YSV{Int64}), 5, 5)
    @test convert(:(YSV{Int64}), [5], Alias) # No conversion has been made.
    @test convert(:(YSN{Int64}), [5, 8], sparse([5, 8]))
    @test convert(:(YSM{Int64}), [5 8; 8 5], Alias)
    @test convert(:(YSE{Int64}), [5 8; 8 5], sparse([5 8; 8 5]))

    #---------------------------------------------------------------------------------------
    # To booleans, any collection.

    @test convert(:(YS{Bool}), 1, true)
    @test convert(:(YSV{Bool}), [1, 0], [true, false])
    @test convert(:(YSV{Bool}), [false, true], Alias)
    # etc.

    #---------------------------------------------------------------------------------------
    # To key-value maps, any iterable of pairs.
    # HERE: test new input grouping opportunity and new error reports.

    # Index keys.
    @test convert(:(K{Float64}), [1 => 5, (2, 8)], OrderedDict(1 => 5.0, 2 => 8.0))

    # Label keys.
    @test convert(
        :(K{Float64}),
        ["a" => 5, (:b, 8), ['c', 13]],
        OrderedDict(:a => 5.0, :b => 8.0, :c => 13.0),
    )

    # Default to symbol index.
    @test convert(:(K{Float64}), [], OrderedDict{Symbol,Float64}())

    # Alias by using the exact same type.
    @test convert(:(K{Float64}), OrderedDict(:a => 5.0, :b => 8.0), Alias)

    # Special binary case.
    @test convert(:(K{:bin}), [1, 2], OrderedSet([1, 2]))
    @test convert(:(K{:bin}), ["a", :b, 'c'], OrderedSet([:a, :b, :c]))
    @test convert(:(K{:bin}), [], OrderedSet{Symbol}())
    @test convert(:(K{:bin}), OrderedSet([:a, :b, :c]), Alias)

    # Accept boolean masks.
    @test convert(:(K{:bin}), Bool[1, 0, 1, 1, 0], OrderedSet([1, 3, 4]))
    @test convert(:(K{:bin}), sparse(Bool[1, 0, 1, 1, 0]), OrderedSet([1, 3, 4]))

    # Still, use Bool as expected for ternary true/false/miss logic.
    @test convert(:(K{Bool}), [1 => true, 3 => false], OrderedDict([1 => true, 3 => false]))

    #---------------------------------------------------------------------------------------
    # To adjacency lists, any nested iterable.

    @test convert(
        :(A{Float64}),
        [1 => [5 => 50, 6 => 60], (2, (7 => 14, 8 => 16))],
        OrderedDict(
            1 => OrderedDict(5 => 50.0, 6 => 60.0),
            2 => OrderedDict(7 => 14.0, 8 => 16.0),
        ),
    )

    @test convert(
        :(A{Float64}),
        ["a" => [:b => 50, 'c' => 60], ("b", (:c => 14, 'a' => 16))],
        OrderedDict(
            :a => OrderedDict(:b => 50.0, :c => 60.0),
            :b => OrderedDict(:c => 14.0, :a => 16.0),
        ),
    )

    @test convert(:(A{Float64}), [], OrderedDict{Symbol,OrderedDict{Symbol,Float64}}())

    @test convert(
        :(A{Float64}),
        OrderedDict(
            :a => OrderedDict(:b => 50.0, :c => 60.0),
            :b => OrderedDict(:c => 14.0, :a => 16.0),
        ),
        Alias,
    )

    # Special binary case.
    @test convert(
        :(A{:bin}),
        [1 => [5, 6], (2, (7, 8))],
        OrderedDict(1 => OrderedSet([5, 6]), 2 => OrderedSet([7, 8])),
    )

    @test convert(
        :(A{:bin}),
        ["a" => [:b, 'c'], ("b", (:c, 'a'))],
        OrderedDict(:a => OrderedSet([:b, :c]), :b => OrderedSet([:c, :a])),
    )

    # Allow singleton keys.
    @test convert(
        :(A{:bin}),
        ["a" => :b, ("b", 'c')],
        OrderedDict(:a => OrderedSet([:b]), :b => OrderedSet([:c])),
    )

    @test convert(:(A{:bin}), [], OrderedDict{Symbol,OrderedSet{Symbol}}())

    @test convert(
        :(A{:bin}),
        OrderedDict(1 => OrderedSet([2, 7]), 2 => OrderedSet([3, 8])),
        Alias,
    )

    # Accept boolean matrices.
    @test convert(
        :(A{:bin}),
        Bool[
            0 1 0
            0 0 0
            1 0 1
        ],
        OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])),
    )

    @test convert(
        :(A{:bin}),
        sparse(Bool[
            0 1 0
            0 0 0
            1 0 1
        ]),
        OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])),
    )

    # Ternary logic.
    @test convert(
        :(A{Bool}),
        [1 => [5 => true, 7 => false], (2, ([7, false], 9 => true))],
        OrderedDict(
            1 => OrderedDict(5 => true, 7 => false),
            2 => OrderedDict(7 => false, 9 => true),
        ),
    )

    #---------------------------------------------------------------------------------------
    # Convenience variable replacing.

    var = 'a'
    @tographdata! var YSV{Float64}
    @test same_type_value(var, :a)

    # ======================================================================================
    # Exposed conversion failures.

    input = 5
    @argfails(
        (@tographdata input YV{Float64}),
        "Could not convert 'input' to either Symbol or Vector{Float64}. \
         The value received is 5 ::$Int.",
    )

    input = 5.0
    @argfails(
        (@tographdata input YSV{Int}),
        "Could not convert 'input' to either Symbol, $Int or Vector{$Int}. \
         The value received is 5.0 ::Float64.",
    )

    input = [0, 1, 2]
    @argfails(
        (@tographdata input YSV{Bool}),
        "Error while attempting to convert 'input' to Vector{Bool} \
         (details further down the stacktrace). \
         Received [0, 1, 2] ::Vector{$Int}.",
    )
    # And down the stacktrace:
    @failswith(
        GraphDataInputs.graphdataconvert(Vector{Bool}, input),
        InexactError(:Bool, Bool, 2)
    )

    #---------------------------------------------------------------------------------------
    # More specific failures.

    gc = GraphDataInputs.graphdataconvert # (don't check first error in stacktrace)

    # Maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    Map = @GraphData Map{Float64}
    @argfails(
        gc(Map, Type),
        "Input for map needs to be iterable.\nReceived: Type ::UnionAll.",
    )
    @argfails(gc(Map, [5]), "Not a 'reference(s) => value' pair at [1]: 5 ::$Int.")
    @argfails(gc(Map, "abc"), "Not a 'reference(s) => value' pair at [1]: 'a' ::Char.")
    @argfails(
        gc(Map, [(Type, "a")]),
        "Cannot interpret node reference as integer index or symbol label: \
         received at [1][left]: Type ::UnionAll.",
    )
    @argfails(
        gc(Map, [(5, "a")]),
        "Expected values of type 'Float64', \
         received instead at [1][right]: \"a\" ::String.",
    )
    @argfails(
        gc(Map, [(5, 8), (:a, 5)]),
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found at [2][left]: :a ::Symbol."
    )
    @argfails(
        gc(Map, [(5, 8), (5, 9)]),
        "Duplicated node reference at [2][left][1]: 5 ::$Int."
    )

    # Binary maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    BinMap = @GraphData Map{:bin}
    @argfails(
        gc(BinMap, Type),
        "Input for binary map needs to be iterable.\n\
         Received: Type ::UnionAll."
    )
    @argfails(
        gc(BinMap, [Type]),
        "Cannot interpret node reference as integer index or symbol label: \
         received at [1]: Type ::UnionAll.",
    )
    @argfails(
        gc(BinMap, [5, :a]),
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found at [2]: :a ::Symbol.",
    )
    @argfails(gc(BinMap, [5, 5]), "Duplicated node reference at [2]: 5 ::$Int.")

    # Adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    Adj = @GraphData Adjacency{Float64}
    @argfails(
        gc(Adj, Type),
        "Input for adjacency map needs to be iterable.\n\
         Received: Type ::UnionAll."
    )
    @argfails(
        gc(Adj, [Type]),
        "Not a 'source(s) => target(s)' pair at [1]: Type ::UnionAll.",
    )
    @argfails(gc(Adj, [5 => 8]), "Not a 'target => value' pair at [1][right]: 8 ::$Int.",)
    @argfails(
        gc(Adj, [5 => [:a => 8]]),
        "The target reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found at [1][right][1][left]: :a ::Symbol.",
    )
    @argfails(
        gc(Adj, ['a' => 8]; ExpectedRefType = Int),
        "Invalid source reference type. \
         Expected $Int (or convertible). \
         Received instead at [1][left]: 'a' ::Char.",
    )
    #  @argfails(
    #  gc((@GraphData A{Float64}), [:a => [:b => 8], 'a' => [:c => 9]]), # HERE: now featured!
    #  "Duplicated key: :a.",
    #  )
    @argfails(
        gc(Adj, [:a => [:b => 8], 'a' => ['b' => 9]]),
        "Duplicate edge specification:\n\
         Previously received: :a → :b (8.0)\n\
         Now received:        :a → :b (9.0) at [2][right][1]: :b ::Symbol.",
    )

    # Binary adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    BinAdj = @GraphData Adjacency{:bin}
    @argfails(
        gc(BinAdj, Type),
        "Input for binary adjacency map needs to be iterable.\n\
         Received: Type ::UnionAll.",
    )
    @argfails(
        gc(BinAdj, [Type]),
        "Not a 'source(s) => target(s)' pair at [1]: Type ::UnionAll.",
    )
    @argfails(
        gc(BinAdj, [5 => [Type]]),
        "Cannot interpret target node reference as integer index or symbol label: \
         received at [1][right][1]: Type ::UnionAll.",
    )
    @argfails(
        gc(BinAdj, [:a => [5]]),
        "The target node reference type for this input \
         was first inferred to be a label (Symbol) based on the received 'a', \
         but an index ($Int) is now found at [1][right][1]: 5 ::$Int.",
    )
    @argfails(
        gc(BinAdj, [5 => 8]; ExpectedRefType = Symbol),
        "Invalid source node reference type. \
         Expected Symbol (or convertible). \
         Received instead at [1][left]: 5 ::$Int.",
    )
    #  @argfails(gc((@GraphData A{:bin}), [5 => [8], 4 + 1 => [9]]), "Duplicated key: 5.") # HERE: now featured!
    @argfails(
        gc(BinAdj, [5 => [8], 4 + 1 => [4 * 2]]),
        "Duplicate edge specification 5 → 8 at [2][right][1]: 8 ::$Int."
    )

    # ======================================================================================
    # Invalid uses.

    @failswith((@tographdata 4 + 5 YSV{Bool}), MethodError, expansion)
    @failswith(
        (@tographdata nope YSV{Bool}),
        UndefVarError => (:nope, TestGraphDataInputs),
    )
    @xargfails(
        (@tographdata input NOPE),
        [
            "Invalid @tographdata target types at",
            "Expected @tographdata var {aliases...}{Target}. Got :NOPE.",
        ],
    )

end

# Do this here after @tographdata has been tested.
@testset "Graph data maps / adjacency lists semantics." begin

    import .GraphDataInputs: accesses, empty_space, inspace

    # Empty list.
    l = []
    l = @tographdata l K{:bin}
    @test nrefs(l) == 0
    @test collect(refs(l)) == []
    @test nrefspace(l) == 0
    @test refspace(l) == OrderedDict{Symbol,Int}()
    @test collect(accesses(l)) == []
    @test empty_space(0)
    @test !inspace((0,), 0) && !inspace((1,), 0)

    # Map indices.
    bin = [1, 3, 5]
    nbin = [1 => "x", 3 => "y", 5 => "z"]
    bin = @tographdata bin K{:bin}
    nbin = @tographdata nbin K{String}
    for l in (bin, nbin)
        @test nrefs(l) == 3
        @test collect(refs(l)) == [1, 3, 5]
        @test nrefspace(l) == 5
        @test refspace(l) == 5
        @test collect(accesses(l)) == [(1,), (3,), (5,)]
    end
    @test all(inspace((i,), 5) for i in 1:5)
    @test !inspace((0,), 5) && !inspace((6,), 5)

    # Map symbols.
    bin = [:a, :c, :e]
    nbin = [:a => 1.0, :c => 2.0, :e => 3.0]
    bin = @tographdata bin K{:bin}
    nbin = @tographdata nbin K{Float64}
    symbols = (string) -> Symbol.(collect(string))
    for l in (bin, nbin)
        @test nrefs(l) == 3
        @test collect(refs(l)) == [:a, :c, :e]
        @test nrefspace(l) == 3
        @test refspace(l) == OrderedDict(:a => 1, :c => 2, :e => 3)
        @test collect(accesses(l)) == [(:a,), (:c,), (:e,)]
        space = refspace(l)
        @test all(inspace((s,), space) for s in symbols("ace"))
        @test !inspace((:x,), space) && !inspace((:y,), space)
    end

    # Adjacency list indices.
    bin = [1 => 2, 3 => [4, 5], 5 => [6, 7]]
    nbin = [1 => [2 => "u"], 3 => [4 => "v", 5 => "w"], 5 => [6 => "x", 7 => "y"]]
    bin = @tographdata bin A{:bin}
    nbin = @tographdata nbin A{String}
    for l in (bin, nbin)
        @test nrefs(l) == 7
        @test nrefs_outer(l) == 3
        @test nrefs_inner(l) == 5

        @test collect(refs(l)) == [1, 2, 3, 4, 5, 6, 7]
        @test collect(refs_outer(l)) == [1, 3, 5]
        @test collect(refs_inner(l)) == [2, 4, 5, 6, 7]

        @test nrefspace(l) == 7
        @test nrefspace_outer(l) == 5
        @test nrefspace_inner(l) == 7

        @test refspace(l) == 7
        @test refspace_outer(l) == 5
        @test refspace_inner(l) == 7

        @test collect(accesses(l)) == [(1, 2), (3, 4), (3, 5), (5, 6), (5, 7)]
    end
    @test all(inspace((i, j), (5, 7)) for i in 1:5, j in 1:7)
    @test all(!inspace((0, i), (5, 7)) && !inspace((i, 0), (5, 7)) for i in 1:5)
    @test all(!inspace((6, i), (5, 7)) && !inspace((i, 8), (5, 7)) for i in 1:5)

    # Adjacency list symbols.
    bin = [:a => :b, :c => [:d, :e], :e => [:f, :g]]
    nbin = [:a => [:b => 1.0], :c => [:d => 2.0, :e => 3.0], :e => [:f => 4.0, :g => 5.0]]
    bin = @tographdata bin A{:bin}
    nbin = @tographdata nbin A{Float64}
    dict = (string) -> OrderedDict(c => i for (i, c) in enumerate(symbols(string)))
    for l in (bin, nbin)
        @test nrefs(l) == 7
        @test nrefs_outer(l) == 3
        @test nrefs_inner(l) == 5

        @test collect(refs(l)) == symbols("abcdefg")
        @test collect(refs_outer(l)) == symbols("ace")
        @test collect(refs_inner(l)) == symbols("bdefg")

        @test nrefspace(l) == 7
        @test nrefspace_outer(l) == 3
        @test nrefspace_inner(l) == 5

        @test refspace(l) == dict("abcdefg")
        @test refspace_outer(l) == dict("ace")
        @test refspace_inner(l) == dict("bdefg")

        @test collect(accesses(l)) == [(:a, :b), (:c, :d), (:c, :e), (:e, :f), (:e, :g)]

        u, v = refspace_outer(l), refspace_inner(l)
        @test all(inspace((i, j), (u, v)) for i in symbols("ace"), j in symbols("bdefg"))
        @test all(
            !inspace((:x, i), (u, v)) && !inspace((i, :y), (u, v)) for i in symbols("ze")
        )
    end

end

@testset "Iteration over graph data input types." begin

    check(a, e) = @test collect(items(a)) == e
    check_nodes(a, e) = @test collect(node_items(a)) == e
    check_edges(a, e) = @test collect(edge_items(a)) == e

    #---------------------------------------------------------------------------------------
    # Vectors.
    check_nodes([], [])
    check([], [])
    #! format: off
    check_nodes([:a, :b, :c], [
        ((1,), :a),
        ((2,), :b),
        ((3,), :c)
    ])
    # Default.
    check([:a, :b, :c], [
        ((1,), :a),
        ((2,), :b),
        ((3,), :c)
    ])
    #! format: on

    #---------------------------------------------------------------------------------------
    # Matrices.
    check([;;], [])
    check_edges([;;], [])
    #! format: off
    check_edges([
       :a :b
       :c :d
     ], [
       ((1, 1), :a),
       ((1, 2), :b),
       ((2, 1), :c),
       ((2, 2), :d),
    ])
    # Default.
    check([
       :a :b
       :c :d
     ], [
       ((1, 1), :a),
       ((1, 2), :b),
       ((2, 1), :c),
       ((2, 2), :d),
    ])
    @failswith(node_items([;;]), "Cannot read node data from a 2D matrix.")
    #! format: on

    #---------------------------------------------------------------------------------------
    # 2D Nested collections.
    # Different interpretation of the same input.
    check_edges([], [])
    check_nodes([], [])
    #! format: off
    check_edges([
       [:a, :b],
       [:c, :d],
     ], [
       ((1, 1), :a),
       ((1, 2), :b),
       ((2, 1), :c),
       ((2, 2), :d),
    ])
    check_nodes([
       [:a, :b],
       [:c, :d],
     ], [
       ((1,), [:a, :b]),
       ((2,), [:c, :d]),
    ])
    # Default.
    check([
       [:a, :b],
       [:c, :d],
     ], [
       ((1,), [:a, :b]),
       ((2,), [:c, :d]),
    ])
    #! format: on

    #---------------------------------------------------------------------------------------
    # Sparse vectors.
    check(sparse([]), [])
    check_nodes(sparse([]), [])
    #! format: off
    check_nodes(sparse([0, 1, 0, 0, 2, 0, 3,  0]), [
       ((2,), 1),
       ((5,), 2),
       ((7,), 3),
    ])
    # Default.
    check(sparse([0, 1, 0, 0, 2, 0, 3,  0]), [
       ((2,), 1),
       ((5,), 2),
       ((7,), 3),
    ])
    #! format: on

    #---------------------------------------------------------------------------------------
    # Sparse matrices.
    check(sparse([;;]), [])
    check(sparse(zeros(3, 3)), [])
    check_edges(sparse([;;]), [])
    check_edges(sparse(zeros(3, 3)), [])
    #! format: off
    check_edges(sparse([
       0 2 0
       1 0 4
       0 3 0
    ]), [
       ((2, 1), 1),
       ((1, 2), 2),
       ((3, 2), 3),
       ((2, 3), 4),
    ])
    # Default.
    check(sparse([
       0 2 0
       1 0 4
       0 3 0
    ]), [
       ((2, 1), 1),
       ((1, 2), 2),
       ((3, 2), 3),
       ((2, 3), 4),
    ])
    #! format: on
    @failswith(node_items(sparse([;;])), "Cannot read node data from a 2D matrix.")

    #---------------------------------------------------------------------------------------
    # Maps.
    check(Dict(), [])
    check(OrderedDict(), [])
    check_nodes(Dict(), [])
    check_nodes(OrderedDict(), [])
    #! format: off
    check_nodes(Dict([
       :a => 1,
       :b => 2,
       :c => 3,
    ]), [
       ((:a,), 1),
       ((:b,), 2),
       ((:c,), 3),
    ])
    # Default.
    check(Dict([
       :a => 1,
       :b => 2,
       :c => 3,
    ]), [
       ((:a,), 1),
       ((:b,), 2),
       ((:c,), 3),
    ])
    #! format: on

    #---------------------------------------------------------------------------------------
    # Adjacency lists.
    e = Dict{Symbol,Dict}()
    oe = OrderedDict{Symbol,Dict}()
    check(e, [])
    check(oe, [])
    check_edges(e, [])
    check_edges(oe, [])
    check_nodes(e, [])
    check_nodes(oe, [])
    # With actual values.
    #! format: off
    check_edges(OrderedDict([
       :a => Dict([:b => 5, :c => 8]),
       :b => Dict([:a => 2]),
       :c => Dict([:c => 0]),
    ]), [
       ((:a, :b), 5),
       ((:a, :c), 8),
       ((:b, :a), 2),
       ((:c, :c), 0),
    ])
    check_nodes(OrderedDict([
       :a => Dict([:b => 5, :c => 8]),
       :b => Dict([:a => 2]),
       :c => Dict([:c => 0]),
    ]), [
       ((:a,), Dict([:b => 5, :c => 8])),
       ((:b,), Dict([:a => 2])),
       ((:c,), Dict([:c => 0])),
    ])
    check_edges(OrderedDict([
       :a => e,
       :b => e,
       :c => e,
    ]), [])
    check_nodes(OrderedDict([
       :a => e,
       :b => e,
       :c => e,
    ]), [
         ((:a,), e),
         ((:b,), e),
         ((:c,), e),
    ])
    # Default to edges if common subtype is a dict.
    check(OrderedDict([
       :a => e,
       :b => e,
       :c => e,
    ]), [])
    # Or else default to nodes.
    check(OrderedDict([
       :a => e,
       :b => e,
       :c => 0,
    ]), [
         ((:a,), e),
         ((:b,), e),
         ((:c,), 0),
    ])
    #! format: on

    #---------------------------------------------------------------------------------------
    # Drop values info to produce binary maps/adjacency lists.

    input = [:a => 5, :c => 8]
    input = @tographdata input Map{Float64}
    result = @tographdata input Map{:bin}
    @test result == OrderedSet([:a, :c])

    input = [:a => [:b => 5, :d => 9], :c => [:a => 8]]
    input = @tographdata input Adjacency{Float64}
    result = @tographdata input Adjacency{:bin}
    @test result == OrderedDict([:a => OrderedSet([:b, :d]), :c => OrderedSet([:a])])

end

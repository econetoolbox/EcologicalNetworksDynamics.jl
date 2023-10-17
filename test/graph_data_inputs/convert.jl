@testset "Graph data conversion." begin

    # ======================================================================================
    # Check convenience macro type conversion.

    same_type_value(a, b) = a isa typeof(b) && a == b
    aliased(a, b) = a === b

    #---------------------------------------------------------------------------------------
    # To scalar symbols.

    input = 'a'
    res = @tographdata input YSV{Float64}
    @test same_type_value(res, :a)

    input = "a"
    res = @tographdata input YSV{Float64}
    @test same_type_value(res, :a)

    input = "a"
    res = @tographdata input Y{}
    @test same_type_value(res, :a)

    # To scalar strings.
    input = 'a'
    res = @tographdata input SYV{String}
    @test same_type_value(res, "a")

    input = :a
    res = @tographdata input SYV{String}
    @test same_type_value(res, "a")

    # (type order matters or the first matching wins)
    input = 'a'
    res = @tographdata input YSV{String} # (Y first wins)
    @test same_type_value(res, :a)

    #---------------------------------------------------------------------------------------
    # To floating point values, any collection.

    input = 5
    res = @tographdata input YSV{Float64}
    @test same_type_value(res, 5.0)

    input = [5]
    res = @tographdata input YSV{Float64}
    @test same_type_value(res, [5.0])

    input = [5, 8]
    res = @tographdata input YSN{Float64}
    @test same_type_value(res, sparse([5.0, 8.0]))

    input = [5 8; 8 5]
    res = @tographdata input YSM{Float64}
    @test same_type_value(res, [5.0 8.0; 8.0 5.0])

    input = [5 8; 8 5]
    res = @tographdata input YSE{Float64}
    @test same_type_value(res, sparse([5.0 8.0; 8.0 5.0]))

    # Aliased version if exact type is provided.
    input = 5.0
    res = @tographdata input YSV{Float64}
    @test same_type_value(res, 5.0)

    input = [5.0]
    res = @tographdata input YSV{Float64}
    @test aliased(input, res) # No conversion has been made.

    input = sparse([5.0, 8.0])
    res = @tographdata input YSN{Float64}
    @test aliased(input, res)

    input = [5.0 8.0; 8.0 5.0]
    res = @tographdata input YSM{Float64}
    @test aliased(input, res)

    input = sparse([5.0 8.0; 8.0 5.0])
    res = @tographdata input YSE{Float64}
    @test aliased(input, res)

    #---------------------------------------------------------------------------------------
    # To integers, any collection.

    input = 5
    res = @tographdata input YSV{Int64}
    @test same_type_value(res, 5)

    input = [5]
    res = @tographdata input YSV{Int64}
    @test aliased(input, res) # No conversion has been made.

    input = [5, 8]
    res = @tographdata input YSN{Int64}
    @test same_type_value(res, sparse([5, 8]))

    input = [5 8; 8 5]
    res = @tographdata input YSM{Int64}
    @test aliased(input, res)

    input = [5 8; 8 5]
    res = @tographdata input YSE{Int64}
    @test same_type_value(res, sparse([5 8; 8 5]))

    #---------------------------------------------------------------------------------------
    # To booleans, any collection.

    input = 1
    res = @tographdata input YS{Bool}
    @test same_type_value(res, true)

    input = [1, 0]
    res = @tographdata input YSV{Bool}
    @test same_type_value(res, [true, false])

    input = [false, true]
    res = @tographdata input YSV{Bool}
    @test aliased(input, res)
    # etc.

    #---------------------------------------------------------------------------------------
    # To key-value maps, any iterable of pairs.

    input = [1 => 5, (2, 8)] # Index keys.
    res = @tographdata input K{Float64}
    @test same_type_value(res, OrderedDict(1 => 5.0, 2 => 8.0))

    input = ["a" => 5, (:b, 8), ['c', 13]] # Label keys.
    res = @tographdata input K{Float64}
    @test same_type_value(res, OrderedDict(:a => 5.0, :b => 8.0, :c => 13.0))

    input = []
    res = @tographdata input K{Float64}
    @test same_type_value(res, OrderedDict{Int64,Float64}()) # Default to integer index.

    # Alias by using the exact same type.
    input = OrderedDict(:a => 5.0, :b => 8.0)
    res = @tographdata input K{Float64}
    @test aliased(input, res)

    # Special binary case.
    input = [1, 2]
    res = @tographdata input K{:bin}
    @test same_type_value(res, OrderedSet([1, 2]))

    input = ["a", :b, 'c']
    res = @tographdata input K{:bin}
    @test same_type_value(res, OrderedSet([:a, :b, :c]))

    input = []
    res = @tographdata input K{:bin}
    @test same_type_value(res, OrderedSet{Int64}())

    input = OrderedSet([:a, :b, :c])
    res = @tographdata input K{:bin}
    @test aliased(input, res)

    # Accept boolean masks.
    input = Bool[1, 0, 1, 1, 0]
    res = @tographdata input K{:bin}
    @test same_type_value(res, OrderedSet([1, 3, 4]))

    input = sparse(Bool[1, 0, 1, 1, 0])
    res = @tographdata input K{:bin}
    @test same_type_value(res, OrderedSet([1, 3, 4]))

    # Still, use Bool as expected for ternary true/false/miss logic.
    input = [1 => true, 3 => false]
    res = @tographdata input K{Bool}
    @test same_type_value(res, OrderedDict([1 => true, 3 => false]))

    #---------------------------------------------------------------------------------------
    # To adjacency lists, any nested iterable.

    input = [1 => [5 => 50, 6 => 60], (2, (7 => 14, 8 => 16))]
    res = @tographdata input A{Float64}
    @test same_type_value(
        res,
        OrderedDict(
            1 => OrderedDict(5 => 50.0, 6 => 60.0),
            2 => OrderedDict(7 => 14.0, 8 => 16.0),
        ),
    )

    input = ["a" => [:b => 50, 'c' => 60], ("b", (:c => 14, 'a' => 16))]
    res = @tographdata input A{Float64}
    @test same_type_value(
        res,
        OrderedDict(
            :a => OrderedDict(:b => 50.0, :c => 60.0),
            :b => OrderedDict(:c => 14.0, :a => 16.0),
        ),
    )

    input = []
    res = @tographdata input A{Float64}
    @test same_type_value(res, OrderedDict{Int64,OrderedDict{Int64,Float64}}())

    input = OrderedDict(
        :a => OrderedDict(:b => 50.0, :c => 60.0),
        :b => OrderedDict(:c => 14.0, :a => 16.0),
    )
    res = @tographdata input A{Float64}
    @test aliased(input, res)

    # Special binary case.
    input = [1 => [5, 6], (2, (7, 8))]
    res = @tographdata input A{:bin}
    @test same_type_value(
        res,
        OrderedDict(1 => OrderedSet([5, 6]), 2 => OrderedSet([7, 8])),
    )

    input = ["a" => [:b, 'c'], ("b", (:c, 'a'))]
    res = @tographdata input A{:bin}
    @test same_type_value(
        res,
        OrderedDict(:a => OrderedSet([:b, :c]), :b => OrderedSet([:c, :a])),
    )

    input = ["a" => :b, ("b", 'c')] # Allow singleton keys.
    res = @tographdata input A{:bin}
    @test same_type_value(res, OrderedDict(:a => OrderedSet([:b]), :b => OrderedSet([:c])))

    input = []
    res = @tographdata input A{:bin}
    @test same_type_value(res, OrderedDict{Int64,OrderedSet{Int64}}())

    input = OrderedDict(1 => OrderedSet([2, 7]), 2 => OrderedSet([3, 8]))
    res = @tographdata input A{:bin}
    @test aliased(input, res)

    # Accept boolean matrices.
    input = Bool[
        0 1 0
        0 0 0
        1 0 1
    ]
    res = @tographdata input A{:bin}
    @test same_type_value(res, OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])))

    input = sparse(Bool[
        0 1 0
        0 0 0
        1 0 1
    ])
    res = @tographdata input A{:bin}
    @test same_type_value(res, OrderedDict(1 => OrderedSet([2]), 3 => OrderedSet([1, 3])))

    # Ternary logic.
    input = [1 => [5 => true, 7 => false], (2, ([7, false], 9 => true))]
    res = @tographdata input A{Bool}
    @test same_type_value(
        res,
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
         The value received is 5 ::Int64.",
    )

    input = 5.0
    @argfails(
        (@tographdata input YSV{Int64}),
        "Could not convert 'input' to either Symbol, Int64 or Vector{Int64}. \
         The value received is 5.0 ::Float64.",
    )

    input = [0, 1, 2]
    @argfails(
        (@tographdata input YSV{Bool}),
        "Error while attempting to convert 'input' to Vector{Bool} \
         (details further down the stacktrace). \
         Received [0, 1, 2] ::Vector{Int64}.",
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
    @argfails(
        gc((@GraphData K{Float64}), Type),
        "Key-value mapping input needs to be iterable.",
    )
    @argfails(gc((@GraphData K{Float64}), [5]), "Not a key-value pair: 5 ::Int64.")
    @argfails(gc((@GraphData K{Float64}), "abc"), "Not a key-value pair: 'a' ::Char.")
    @argfails(
        gc((@GraphData K{Float64}), [(Type, "a")]),
        "Cannot convert key to integer or symbol label: \
         received Type ::UnionAll.",
    )
    @argfails(
        gc((@GraphData K{Float64}), [(5, "a")]),
        "Map value at key '5' cannot be converted to 'Float64': \
         received \"a\" ::String.",
    )
    @argfails(
        gc((@GraphData K{Float64}), [(5, 8), (:a, 5)]),
        "Map key cannot be converted to 'Int64': received :a ::Symbol.",
    )
    @argfails(gc((@GraphData K{Float64}), [(5, 8), (5, 9)]), "Duplicated key: 5.")

    # Binary maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @argfails(gc((@GraphData K{:bin}), Type), "Binary mapping input needs to be iterable.")
    @argfails(
        gc((@GraphData K{:bin}), [Type]),
        "Cannot convert key to integer or symbol label: \
         received Type ::UnionAll.",
    )
    @argfails(
        gc((@GraphData K{:bin}), [5, :a]),
        "Map key cannot be converted to 'Int64': \
         received :a ::Symbol.",
    )
    @argfails(gc((@GraphData K{:bin}), [5, 5]), "Duplicated key: 5.")

    # Adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @argfails(
        gc((@GraphData A{Float64}), Type),
        "Adjacency list input needs to be iterable.",
    )
    @argfails(
        gc((@GraphData A{Float64}), [Type]),
        "Not a key-value pair: Type ::UnionAll.",
    )
    @argfails(
        gc((@GraphData A{Float64}), [5 => 8]),
        "Error while parsing adjacency list input at key '5' \
         (see further down the stacktrace).", # (see map error above)
    )
    @argfails(
        gc((@GraphData A{Float64}), [5 => [:a => 8]]),
        "Error while parsing adjacency list input at key '5' \
         (see further down the stacktrace).",
    )
    # (down the stacktrace)
    @argfails(
        gc((@GraphData K{Float64}), ['a' => 8]; expected_I = Int64),
        "Expected 'Int64' as key types, got 'Symbol' instead \
         (inferred from first key: 'a' ::Char).",
    )
    @argfails(
        gc((@GraphData A{Float64}), [:a => [:b => 8], 'a' => [:c => 9]]),
        "Duplicated key: :a.",
    )

    # Binary adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @argfails(
        gc((@GraphData A{:bin}), Type),
        "Binary adjacency list input needs to be iterable.",
    )
    @argfails(gc((@GraphData A{:bin}), [Type]), "Not a key-value pair: Type ::UnionAll.",)
    @argfails(
        gc((@GraphData A{:bin}), [5 => [Type]]),
        "Error while parsing adjacency list input at key '5' \
         (see further down the stacktrace).", # (see binary map error above)
    )
    @argfails(
        gc((@GraphData A{:bin}), [:a => [5]]),
        "Error while parsing adjacency list input at key 'a' \
         (see further down the stacktrace).",
    )
    # (down the stacktrace)
    @argfails(
        gc((@GraphData K{:bin}), [5]; expected_I = Symbol),
        "Expected 'Symbol' as key types, got 'Int64' instead \
         (inferred from first key: 5 ::Int64).",
    )
    @argfails(gc((@GraphData A{:bin}), [5 => [8], 4 + 1 => [9]]), "Duplicated key: 5.",)

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
    @test refspace(l) == 0
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

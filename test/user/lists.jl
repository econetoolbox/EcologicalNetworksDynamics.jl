module Lists

using EcologicalNetworksDynamics.NetworkFramework:
    NF, SparseMatrix, Map, Adjacency, BinMap, BinAdjacency, convert, try_convert
# /!\ `convert !== Base.convert` in this module.

using EcologicalNetworksDynamics.Tests: @test_err, @checkfails, @listfails

using Test
using SparseArrays
using OrderedCollections

cv(type, input) = convert(type, input)
cv(type, input, ExpectedRefType) = convert(type, input; ExpectedRefType)

@testset "Parsing maps and adjacency lists." begin

    # Binary maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @listfails( #  :not_iterable
        cv(BinMap, Type),
        Type, [], "Input for binary map needs to be iterable.")

    @test_err(cv(BinMap, Type), # (check full message with empty path)
        """
        Input for binary map needs to be iterable.
        Received: $Type  ::$UnionAll\
        """)

    @listfails( #  :pair_as_iterable
        cv(BinMap, :a => :b),
        (:a => :b), [],
        "This pair is just considered an iterable in this context, \
         which may be confusing. \
         Consider grouping with an explicit vector instead like [:a, :b]."
    )

    @listfails( #  :not_a_ref
        cv(BinMap, [Type]), Type, [1],
        "Cannot interpret node reference as integer index or symbol label.")

    @test_err(cv(BinMap, [Type]), # (check full message with 1-level path)
        """
        In the provided input at [1]:
        Cannot interpret node reference as integer index or symbol label.
        Received: $Type  ::$UnionAll\
        """)

    @listfails( #  :invalid_index
        cv(BinMap, [-1]),
        -1, [1], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type
        cv(BinMap, [5], Symbol),
        5, [1], "Invalid node reference type. \
         Expected Symbol (or convertible).")

    @listfails( #  :unexpected_ref_type
        cv(BinMap, [:label], Int),
        :label, [1],
        "Invalid node reference type. \
         Expected $Int (or convertible).")

    @listfails( #  :inconsistent_ref_type
        cv(BinMap, [5, :a]),
        :a, [2],
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found.",
    )

    # :duplicate_node
    @listfails(cv(BinMap, [5, 5]), 5, [2], "Duplicated node reference.")

    # (from boolean masks)
    @listfails( # :boolean_label
        cv(BinMap, Bool[0, 0, 1, 0, 1], Symbol),
        Bool[0, 0, 1, 0, 1], [],
        "A label-indexed binary map cannot be produced from boolean vectors.")

    # :unexpected_ref_type for boolean masks is tested when used for parsing grouped refs.

    # Maps. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    M = Map{Float64}

    @listfails( #  :not_iterable
        cv(M, Type),
        Type, [], "Input for map needs to be iterable.")

    #  :not_a_pair
    @listfails(cv(M, [5]), 5, [1], "Not a 'reference(s) => value' pair.")
    @listfails(cv(M, "abc"), 'a', [1], "Not a 'reference(s) => value' pair.")

    @listfails( #  :not_a_ref (plain)
        cv(M, [(Type, "a")]),
        Type, [1, :left],
        "Cannot interpret node reference as integer index or symbol label.")

    @test_err(cv(M, [(Type, "a")]), # (check full message with 2-levels path)
        """
        In the provided input at [1][left]:
        Cannot interpret node reference as integer index or symbol label.
        Received: $Type  ::$UnionAll\
        """)

    @listfails( #  :invalid_index (plain)
        cv(M, [(-1, "a")]),
        -1, [1, :left], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (plain)
        cv(M, [(5, "a")], Symbol),
        5, [1, :left],
        "Invalid node reference type. Expected Symbol (or convertible).")

    @listfails( #  :unexpected_ref_type (plain)
        cv(M, [(:label, "a")], Int),
        :label, [1, :left],
        "Invalid node reference type. Expected $Int (or convertible).")

    @listfails( #  :inconsistent_ref_type (plain)
        cv(M, [(5, 8), (:a, 5)]),
        :a, [2, :left],
        "The node reference type for this input \
         was first inferred to be an index ($Int) based on the received '5', \
         but a label (Symbol) is now found.")

    @listfails( #  :inconsistent_ref_type (plain)
        cv(M, [(:a, 5), (8, 5)]),
        8, [2, :left],
        "The node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( #  :not_a_ref (grouped)
        cv(M, [[:a, Type] => 5]),
        Type, [1, :left, :2],
        "Cannot interpret node reference as integer index or symbol label.")

    @listfails( #  :invalid_index (grouped)
        cv(M, [[:a, -1] => 5]),
        -1, [1, :left, 2], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (grouped)
        cv(M, [[5, :b] => 8], Symbol),
        5, [1, :left, 1], "Invalid node reference type. Expected Symbol (or convertible).")

    @listfails( #  :inconsistent_ref_type (grouped)
        cv(M, [:a => 5, [:b, 3] => 8]),
        3, [2, :left, 2],
        "The node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( #  :duplicate_node (grouped)
        cv(M, [[:a, :b, :a] => 5]),
        :a, [1, :left, 3], "Duplicated node reference.")

    @listfails( #  :boolean_label
        cv(M, [:a => 5, Bool[0, 1, 1] => 8], Symbol),
        Bool[0, 1, 1], [2, :left],
        "A label-indexed group of nodes cannot be produced from boolean vectors.")

    @listfails( #  :inconsistent_ref_type (bool)
        cv(M, [:a => 5, Bool[0, 1, 1] => 8]),
        Bool[0, 1, 1], [2, :left],
        "The group of nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found.")

    @listfails( #  :not_a_value
        cv(M, [(5, "a")]),
        "a", [1, :right], "Expected values of type 'Float64'.")

    @listfails( #  :duplicate_node
        cv(M, [[:a, :b] => 5, [:c, :a] => 8]),
        :a, [2, :left, 2],
        "Duplicated node reference :\n\
         Collected before: a => 5.0\n\
         Collecting now  : a => 8  ::$Int.")

    # Binary adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    @listfails( #  :not_iterable
        cv(BinAdjacency, Type),
        Type, [], "Input for binary adjacency map needs to be iterable.")

    @listfails( #  :not_a_pair
        cv(BinAdjacency, [Type]),
        Type, [1], "Not a 'source(s) => target(s)' pair.")

    @listfails( #  :not_a_ref (plain source)
        cv(BinAdjacency, [Type => 5]),
        Type, [1, :left],
        "Cannot interpret source node reference as integer index or symbol label.")

    @listfails( #  :invalid_index (plain source)
        cv(BinAdjacency, [-1 => 5]),
        -1, [1, :left], "Integer reference must be a positive index.")

    @listfails( #  :not_a_ref (plain target)
        cv(BinAdjacency, [5 => Type]),
        Type, [1, :right],
        "Cannot interpret target node reference as integer index or symbol label.")

    @listfails( #  :invalid_index (plain target)
        cv(BinAdjacency, [5 => -1]),
        -1, [1, :right], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (plain source)
        cv(BinAdjacency, [:a => :b], Int),
        :a, [1, :left],
        "Invalid source node reference type. Expected $Int (or convertible).")

    @listfails( #  :unexpected_ref_type (plain target)
        cv(BinAdjacency, [1 => 2], Symbol),
        1, [1, :left],
        "Invalid source node reference type. Expected Symbol (or convertible).")

    @listfails( #  :inconsistent_ref_type (plain source)
        cv(BinAdjacency, [:a => :b, 2 => :c]),
        2, [2, :left],
        "The source node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( #  :inconsistent_ref_type (plain target)
        cv(BinAdjacency, [1 => :b]),
        :b, [1, :right],
        "The target node reference type for this input \
         was first inferred to be an index ($Int) based on the received '1', \
         but a label (Symbol) is now found.")

    @listfails( #  :not_a_ref (grouped sources)
        cv(BinAdjacency, [2 => 5, [1, Type] => 3]),
        Type, [2, :left, 2],
        "Cannot interpret source node reference as integer index or symbol label.")

    @listfails( #  :invalid_index (grouped sources)
        cv(BinAdjacency, [2 => 5, [1, -1] => 3]),
        -1, [2, :left, 2], "Integer reference must be a positive index.")

    @listfails( #  :not_a_ref (grouped targets)
        cv(BinAdjacency, [2 => 5, 1 => [3, Type]]),
        Type, [2, :right, 2],
        "Cannot interpret target node reference as integer index or symbol label.")

    @listfails( #  :invalid_index (grouped targets)
        cv(BinAdjacency, [2 => 5, 1 => [3, -1]]),
        -1, [2, :right, 2], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (grouped sources)
        cv(BinAdjacency, [[:a] => 5], Int),
        :a, [1, :left, 1],
        "Invalid source node reference type. Expected $Int (or convertible).")

    @listfails( #  :unexpected_ref_type (grouped targets)
        cv(BinAdjacency, [:a => [:b, :c, 4]], Symbol),
        4, [1, :right, 3],
        "Invalid target node reference type. Expected Symbol (or convertible).")

    @listfails( #   :pair_as_iterable (grouped sources)
        cv(BinAdjacency, [(:a => :b) => :c], Symbol),
        (:a => :b), [1, :left],
        "This pair is just considered an iterable in this context, \
         which may be confusing. \
         Consider grouping with an explicit vector instead like [:a, :b].")

    @listfails( #   :pair_as_iterable (grouped targets)
        cv(BinAdjacency, [:a => :b => :c], Symbol),
        (:b => :c), [1, :right],
        "This pair is just considered an iterable in this context, \
         which may be confusing. \
         Consider grouping with an explicit vector instead like [:b, :c].")

    @listfails( #  :inconsistent_ref_type (grouped sources)
        cv(BinAdjacency, [[1, :b, 3] => 4]),
        :b, [1, :left, 2],
        "The source node reference type for this input \
         was first inferred to be an index ($Int) based on the received '1', \
         but a label (Symbol) is now found.")

    @listfails( #  :inconsistent_ref_type (grouped targets)
        cv(BinAdjacency, [:a => [:b, :c, 4]]),
        4, [1, :right, 3],
        "The target node reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( #  :duplicate_node (grouped sources)
        cv(BinAdjacency, [:a => :b, :a => :c, [:b, :c, 'b'] => :a]),
        'b', [3, :left, 3], "Duplicated source node reference.")

    @listfails( #  :boolean_label (sources)
        cv(BinAdjacency, [:a => :b, Bool[1, 1, 0] => :c], Symbol),
        Bool[1, 1, 0], [2, :left],
        "A label-indexed group of source nodes cannot be produced from boolean vectors.")

    @listfails( #  :boolean_label (targets)
        cv(BinAdjacency, [:a => :b, :c => Bool[1, 1, 0]], Symbol),
        Bool[1, 1, 0], [2, :right],
        "A label-indexed group of target nodes cannot be produced from boolean vectors.")

    @listfails( #  :inconsistent_ref_type (bool sources)
        cv(BinAdjacency, [:a => :b, Bool[1, 1, 0] => :c]),
        Bool[1, 1, 0], [2, :left],
        "The group of source nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found.")

    @listfails( #  :inconsistent_ref_type (bool targets)
        cv(BinAdjacency, [:a => :b, :c => Bool[1, 1, 0]]),
        Bool[1, 1, 0], [2, :right],
        "The group of target nodes reference type for this input \
         was first inferred to be a label (Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found.")

    @listfails( #  :duplicate_edge
        cv(BinAdjacency, [5 => [8], 4 + 1 => [4 * 2]]),
        8, [2, :right, 1], "Duplicate edge specification 5 → 8.")

    @listfails( #  :duplicate_edge
        cv(BinAdjacency, [[:a, :b] => [:b], :a => [:c, :b]]),
        :b, [2, :right, 2], "Duplicate edge specification :a → :b.")

    @listfails( #  :no_targets
        cv(BinAdjacency, [[1, 2] => []]),
        [], [1, :right], "No target provided for source 1.")

    @listfails( #  :no_targets
        cv(BinAdjacency, [:a => [:b], :c => ()]),
        (), [2, :right], "No target provided for source :c.")

    @listfails( #  :no_sources
        cv(BinAdjacency, [[] => [1, 2]]),
        [], [1, :left], "No sources provided.")

    @listfails( #  :boolean_label
        cv(BinAdjacency, Bool[1 0 1], Symbol),
        Bool[1 0 1], [],
        "A label-indexed binary adjacency list cannot be produced from boolean matrices.")

    # Adjacency lists. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    A = Adjacency{Float64}

    @listfails( #  :not_iterable
        cv(A, Type),
        Type, [], "Input for adjacency map needs to be iterable.")

    @listfails( #  :not_a_pair
        cv(A, [Type]),
        Type, [1], "Not a 'source(s) => target(s)' pair.")

    @listfails( #  :not_a_pair (plain sources) : pick :not_a_ref
        cv(A, [Type => 5]),
        Type, [1, :left],
        "Cannot interpret source reference as integer index or symbol label.")

    @listfails( #  :not_a_pair (plain sources) : pick :invalid_index
        cv(A, [-1 => 5]),
        -1, [1, :left], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (plain source)
        cv(A, [:a => 5], Int),
        :a, [1, :left], "Invalid source reference type. Expected $Int (or convertible).")

    @listfails( # :inconsistent_ref_type (plain source)
        cv(A, [(:a => 5) => :b, (1 => 8) => :c]),
        1, [2, :left, :left],
        "The source reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( # :not_a_value (plain source)
        cv(A, [(:a => 5im) => :b]),
        5im, [1, :left, :right], "Expected values of type '$Float64'.")

    @listfails( # :not_a_pair (map source) : pick :not_a_ref
        cv(A, [[Type] => 5]),
        Type, [1, :left, 1],
        "Cannot interpret source reference as integer index or symbol label.")

    @listfails( # :not_a_pair (map source) : pick :invalid_index
        cv(A, [[-1] => 5]),
        -1, [1, :left, 1], "Integer reference must be a positive index.")

    @listfails( # :unexpected_ref_type (map source)
        cv(A, [[5] => 8], Symbol),
        5, [1, :left, 1],
        "Invalid source reference type. Expected $Symbol (or convertible).")

    @listfails( # :inconsistent_ref_type (map source)
        cv(A, [[5, :a] => 8]),
        :a, [1, :left, 2],
        "The source reference type for this input \
         was first inferred to be an index ($Int) \
         based on the received '5', but a label ($Symbol) is now found.")

    @listfails( # :duplicate_node (map source)
        cv(A, [[:a => 5, :a => 8] => :b]),
        :a, [1, :left, 2, :left, 1],
        "Duplicated source reference :\n\
         Collected before: a => 5.0\n\
         Collecting now  : a => 8  ::$Int.")

    @listfails( # :duplicate_node (map source)
        cv(A, [[:a => 5, [:b, :b] => 8] => :c]),
        :b, [1, :left, 2, :left, 2], "Duplicated source reference.")

    @listfails( # :duplicate_node (map source)
        cv(A, [[:a, :a] => 8]),
        :a, [1, :left, 2], "Duplicated source reference.")

    @listfails( # :boolean_label (map source)
        cv(A, [Bool[0, 1, 1, 0] => (2 => 10)], Symbol),
        Bool[0, 1, 1, 0], [1, :left],
        "A label-indexed group of sources cannot be produced from boolean vectors.")

    @listfails( # :inconsistent_ref_type (map source)
        cv(A, [:a => (:b => 5), Bool[0, 1, 1, 0] => (2 => 10)]),
        Bool[0, 1, 1, 0], [2, :left],
        "The group of sources reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but a boolean vector (only yielding indices) is now found.")

    @listfails( # :not_a_value (plain source)
        cv(A, [[:a => 5im] => :b]),
        5im, [1, :left, 1, :right], "Expected values of type '$Float64'.")

    # TODO: better explain that the duplication comes from the boolean?
    # (although this really is a weird input)
    @listfails( # :duplicate_node (map source)
        cv(A, [[1 => 5, 2 => 8, Bool[0, 1, 1] => 9] => 3]),
        2, [1, :left, 3, :left, 1],
        "Duplicated source reference :\n\
         Collected before: 2 => 8.0\n\
         Collecting now  : 2 => 9  ::$Int.")

    # # # ≈ same on the target side # # #
    # TODO: I am having a hard time making sure that all error paths are covered.
    # Design a more systematic way?

    @listfails( #  :not_a_pair (plain targets) : pick :not_a_ref
        cv(A, [5 => Type]),
        Type, [1, :right],
        "Cannot interpret target reference as integer index or symbol label.")

    @listfails( #  :not_a_pair (plain targets) : pick :invalid_index
        cv(A, [5 => -1]),
        -1, [1, :right], "Integer reference must be a positive index.")

    @listfails( #  :unexpected_ref_type (plain target)
        cv(A, [1 => (:a => 5)], Int),
        :a, [1, :right, :left],
        "Invalid target reference type. Expected $Int (or convertible).")

    @listfails( # :inconsistent_ref_type (plain target)
        cv(A, [:a => (:b => 5), :c => (3 => 8)]),
        3, [2, :right, :left],
        "The target reference type for this input \
         was first inferred to be a label ($Symbol) based on the received ':a', \
         but an index ($Int) is now found.")

    @listfails( # :not_a_value (plain target)
        cv(A, [:a => (:b => 5im)]),
        5im, [1, :right, :right], "Expected values of type '$Float64'.")

    @listfails( # :not_a_pair (map target) : pick :not_a_ref
        cv(A, [5 => [Type]]),
        Type, [1, :right, 1],
        "Cannot interpret target reference as integer index or symbol label.")

    @listfails( # :not_a_pair (map target) : pick :invalid_index
        cv(A, [5 => [-1]]),
        -1, [1, :right, 1], "Integer reference must be a positive index.")

    @listfails( # :unexpected_ref_type (map target)
        cv(A, [:a => [2]], Symbol),
        2, [1, :right, 1],
        "Invalid target reference type. Expected $Symbol (or convertible).")

    @listfails( # :duplicate_node (map target)
        cv(A, [:a => [:b => 5, :b => 8]]),
        :b, [1, :right, 2, :left, 1],
        "Duplicated target reference :\n\
         Collected before: b => 5.0\n\
         Collecting now  : b => 8  ::$Int.")

    @listfails( # :duplicate_node (map target)
        cv(A, [:a => [:b => 5, [:c, :c] => 8]]),
        :c, [1, :right, 2, :left, 2], "Duplicated target reference.")

    @listfails( # :not_a_value (plain target)
        cv(A, [:a => [:b => 5im]]),
        5im, [1, :right, 1, :right], "Expected values of type '$Float64'.",)

    # # # Specific to Adjacency maps # # #

    @listfails( # :two_values
        cv(A, [(:a => 5) => [:b => 8]]),
        (:a => 5) => [:b => 8], [1],
        "Cannot associate values to both source and target ends of edges:\n\
         Left : :a => 5  ::$Pair{$Symbol, $Int}\n\
         Right: [:b => 8]  ::$Vector{$Pair{$Symbol, $Int}}")

    @listfails( # :no_value
        cv(A, [:a => [:b, :c]]),
        :a => [:b, :c], [1],
        "No values found for either source or target end of edges:\n\
         Left : :a  ::$Symbol\n\
         Right: [:b, :c]  ::$Vector{$Symbol}")

    @listfails( # :duplicate_edge
        cv(A, [:a => [:b => 5, :c => 8], [:a => 13] => [:c, :d]]),
        :c, [2, :right, 1],
        "Duplicate edge specification:\n\
         Collected before: :a → :c (8.0)\n\
         Collecting now  : :a → :c (13.0).")

    @listfails( # :no_targets
        cv(A, [:a => []]),
        (), [1, :left, 1], "No target provided for `target => value` pair.")
    # TODO: fix the received value: should be '[]' not this fake '()'.

    @listfails( # :no_sources
        cv(A, [[] => :b]),
        [], [1, :left, 0], "No sources provided.")

end

end

@testset "Graph data checking." begin

    # ======================================================================================
    # Symbol checking.

    input = :a
    @test @check_symbol input (a, b, c)
    @test @check_symbol input (a,)

    # Convenience alternate forms.
    @test @check_symbol input (:a, :b, :c)
    @test @check_symbol input (:a,)
    @test @check_symbol input [a, b, c]
    @test @check_symbol input [:a, :b, :c]
    @test @check_symbol input [a]
    @test @check_symbol input [:a]
    @test @check_symbol input a # (slightly confusing)
    @test @check_symbol input :a # (clearer)

    # Exposed failures.
    @failswith(
        (@check_symbol input (x, y, z)),
        BlueprintCheckFailure("Invalid symbol received for 'input': :a. \
                             Expected either :x, :y or :z instead."),
    )
    @failswith(
        (@check_symbol input x),
        BlueprintCheckFailure("Invalid symbol received for 'input': :a. \
                             Expected :x instead.")
    )

    # Incorrect use.
    @failswith(
        (@check_symbol nope (a, b, c)),
        UndefVarError => (:nope, TestGraphDataInputs)
    )
    @failswith((@check_symbol 4 + 5 (a, b, c)), MethodError, expansion)
    @xargfails(
        (@check_symbol input (4 + 5)),
        [
            "Invalid @build_from_symbol macro use at",
            "Expected a list of symbols. Got :(4 + 5).",
        ]
    )
    @xargfails(
        (@check_symbol input (a, 4 + 5, c)),
        [
            "Invalid @build_from_symbol macro use at",
            "Expected a list of symbols. Got :((a, 4 + 5, c)).",
        ]
    )

    # ======================================================================================
    # Size checking.

    # Vector.
    input = [1, 2, 3]
    @test @check_size input 3
    @test @check_size input (3,)
    @check_size input Any
    @check_size input (Any,)
    n = 3
    @test @check_size input n
    @check_size input (n,)

    # Matrices.
    input = [1 1 1; 2 2 2]
    m = 2
    @test @check_size input (2, 3)
    @test @check_size input (2, n)
    @test @check_size input (m, 3)
    @test @check_size input (m, n)
    @test @check_size input (Any, n)
    @test @check_size input (m, Any)
    @test @check_size input (Any, 3)
    @test @check_size input (2, Any)
    @test @check_size input (Any, Any)

    # Pass variable as expected size.
    es = (2, 3)
    @test @check_size input es

    # Exposed failures.
    input = [1, 2]
    @failswith(
        (@check_size input 3),
        BlueprintCheckFailure("Invalid size for parameter 'input': \
                               expected (3,), got (2,)."),
    )
    input = [1 1; 2 2]
    @failswith(
        (@check_size input (Any, 3)),
        BlueprintCheckFailure("Invalid size for parameter 'input': \
                               expected (Any, 3), got (2, 2)."),
    )

    # Invalid uses.
    @failswith((@check_size nope (Any, 3)), UndefVarError => (:nope, TestGraphDataInputs))
    @failswith((@check_size input nope), UndefVarError => (:nope, TestGraphDataInputs))
    @failswith(
        (@check_size input "nope"), # TODO: not a super-satifsying error, but good enough.
        BlueprintCheckFailure("Invalid size for parameter 'input': \
                               expected (\"nope\",), got (2, 2)."),
    )
    input = 5
    @failswith(
        (@check_size input (2, 3)),
        BlueprintCheckFailure("Invalid size for parameter 'input': \
                               expected (2, 3), got ().")
    )
    input = :a
    @failswith((@check_size input (2, 3)), MethodError) # (size(::Symbol))


    # ======================================================================================
    # Template checking: reminder:
    #  ·: missing value.
    #  0: non-missing zero value.
    #  N: non-missing non-zero value.

    #---------------------------------------------------------------------------------------
    # Vectors.

    template = sparse([0, 0, 1, 0, 1, 0, 1]) # (template with '·' and 'N')
    a = sparse([0, 0, 2, 0, 3, 0, 4])        # (value with '·' and 'N')
    b = sparse([0, 0, 0, 0, 3, 0, 4])        # (value with '·' and 'N')

    @test @check_template a template :item # 'N' on 'N' and '·' on '·': ✓
    a[3] -= 2                              # (introduce '0' in value)
    @test @check_template a template :item # '0' on 'N': ✓
    @test @check_template b template :item # '·' on 'N': ✓
    template[end] -= 1                     # (introduce '0' in template)
    @test @check_template a template :item # 'N' on '0': ✓
    template[3] -= 1                       # (another '0' in template)
    @test @check_template a template :item # '0' on '0': ✓
    @test @check_template b template :item # '·' on '0': ✓

    # Exposed failures.
    a[4] = 5 # 'N' on '·': 🗙
    @failswith(
        (@check_template a template :item),
        BlueprintCheckFailure("Non-missing value found for 'a' at node index [4] (5), \
                               but the template for 'item' only allows values \
                               at the following indices:\n  [3, 5, 7]")
    )
    a[4] -= 5 # '0' on '·': 🗙
    @failswith(
        (@check_template a template :item),
        BlueprintCheckFailure("Non-missing value found for 'a' at node index [4] (0), \
                               but the template for 'item' only allows values \
                               at the following indices:\n  [3, 5, 7]")
    )

    #---------------------------------------------------------------------------------------
    # Matrices.

    template = sparse([
        0 1 1 # (template with '·' and 'N')
        1 0 0
        0 1 0
    ])
    a = sparse([
        0 2 3 # (value with '·' and 'N')
        4 0 0
        0 5 0
    ])
    b = sparse([
        0 0 3 # (value with '·' and 'N')
        4 0 0
        0 5 0
    ])
    @test @check_template a template :item # 'N' on 'N' and '·' on '·': ✓
    a[1, 2] -= 2                           # (introduce '0' in value)
    @test @check_template a template :item # '0' on 'N': ✓
    @test @check_template b template :item # '·' on 'N': ✓
    template[3, 2] -= 1                    # (introduce '0' in template)
    @test @check_template a template :item # 'N' on '0': ✓
    template[1, 2] -= 1                    # (another '0' in template)
    @test @check_template a template :item # '0' on '0': ✓
    @test @check_template b template :item # '·' on '0': ✓

    # Exposed failures.
    a[2, 2] = 6 # 'N' on '·': 🗙
    @failswith(
        (@check_template a template :item),
        BlueprintCheckFailure("Non-missing value found for 'a' at edge index [2, 2] (6), \
                               but the template for 'item' only allows values \
                               at the following indices:\n  \
                               [(2, 1), (1, 2), (3, 2), (1, 3)]"),
    )
    a[2, 2] -= 6 # '0' on '·': 🗙
    @failswith(
        (@check_template a template :item),
        BlueprintCheckFailure("Non-missing value found for 'a' at edge index [2, 2] (0), \
                               but the template for 'item' only allows values \
                               at the following indices:\n  \
                               [(2, 1), (1, 2), (3, 2), (1, 3)]"),
    )

    #---------------------------------------------------------------------------------------
    # Invalid uses.

    @failswith(
        (@check_template nope template :item),
        UndefVarError => (:nope, TestGraphDataInputs)
    )
    @failswith(
        (@check_template a nope :item),
        UndefVarError => (:nope, TestGraphDataInputs)
    )
    # TODO: improve the following errors?
    @failswith((@check_template a 4 + 5 :item), MethodError)
    @failswith((@check_template 4 + 5 template :item), MethodError, expansion)
    a = 5
    @failswith(
        (@check_template a template :item),
        BlueprintCheckFailure("Invalid size for parameter 'a': expected (3, 3), got ()."),
    )
    a = :a
    @failswith((@check_template a template :item), MethodError)

    # ======================================================================================
    # Key-value maps and adjacency lists.

    gc = GraphDataInputs.graphdataconvert # (don't check first error in stacktrace)

    #---------------------------------------------------------------------------------------
    # Maps.

    full = sparse([1, 0, 0, 0, 1])
    partial = sparse([1, 0, 1, 0, 1])
    neg = sparse([0, 1, 0, 1, 0])

    # With indices.
    for v in [
        gc((@GraphData K{Float64}), [1 => 5, 5 => 8]),
        gc((@GraphData K{:bin}), [1, 5]), #
    ]
        # Check index space.
        @test @check_list_refs v :item 5
        @failswith(
            (@check_list_refs v :item 3),
            BlueprintCheckFailure("Invalid 'item' node index in 'v'. \
                                   Index '5' does not fall within the valid range 1:3.")
        )
        # Check against a template.
        @test @check_list_refs v :item template(partial)
        @failswith(
            (@check_list_refs v :item 5 template(neg)),
            BlueprintCheckFailure("Invalid 'item' node index in 'v': 1. \
                                   Valid nodes indices for this template are:\n  [2, 4]")
        )
    end

    # Check densely against a template.
    v = gc((@GraphData K{Float64}), [1 => 5, 5 => 8])
    @test @check_list_refs v :item template(full) dense
    @failswith(
        (@check_list_refs v :item template(partial) dense),
        BlueprintCheckFailure("Missing 'item' node index in 'v': \
                               no value specified for 3.")
    )

    # Check densely against bare reference space.
    v = gc((@GraphData K{Float64}), [1 => 5, 2 => 8])
    @test @check_list_refs v :item 2 dense
    @failswith(
        (@check_list_refs v :item 5 dense),
        BlueprintCheckFailure("Missing 'item' node index in 'v': \
                               no value specified for 3.")
    )

    # Empty space.
    @failswith(
        (@check_list_refs v :item 0),
        BlueprintCheckFailure("No possible valid node index in 'v' like 1: \
                               the reference space for 'item' is empty.")
    )

    # With labels.
    full_index = Dict(Symbol(s) => i for (i, s) in enumerate("abcde"))
    part_index = Dict(Symbol(s) => i for (i, s) in enumerate("abc"))
    for v in [
        gc((@GraphData K{Float64}), [:a => 5, :e => 8]),
        gc((@GraphData K{:bin}), [:a, :e]), #
    ]
        # Check labels space.
        @test @check_list_refs v :item full_index
        @failswith(
            (@check_list_refs v :item part_index),
            BlueprintCheckFailure("Invalid 'item' node label in 'v'. \
                                   Expected either :a, :b or :c, got instead: :e.")
        )
        # Check against a template.
        @test @check_list_refs v :item full_index template(partial)
        @failswith(
            (@check_list_refs v :item full_index template(neg)),
            BlueprintCheckFailure("Invalid 'item' node label in 'v': :a. \
                                   Valid nodes labels for this template are:\n  [:b, :d]")
        )
    end

    # Check densely against a template.
    v = gc((@GraphData K{Float64}), [:a => 5, :e => 8])
    @test @check_list_refs v :item full_index template(full) dense
    @failswith(
        (@check_list_refs v :item full_index template(partial) dense),
        BlueprintCheckFailure("Missing 'item' node label in 'v': \
                               no value specified for :c.")
    )

    # Check densely against bare reference space.
    v = gc((@GraphData K{Float64}), [:a => 5, :b => 8, :c => 13])
    @test @check_list_refs v :item part_index dense
    @failswith(
        (@check_list_refs v :item full_index dense),
        BlueprintCheckFailure("Missing 'item' node label in 'v': \
                               no value specified for :d.")
    )

    # Empty space.
    @failswith(
        (@check_list_refs v :item Dict{Symbol,Int64}()),
        BlueprintCheckFailure("No possible valid node label in 'v' like :a: \
                               the reference space for 'item' is empty.")
    )

    # Indices space automatically inferred from labels index.
    v = gc((@GraphData K{Float64}), [1 => 5, 2 => 8])
    @test @check_list_refs v :item part_index

    #---------------------------------------------------------------------------------------
    # Adjacency lists.

    full = sparse([
        0 0 0 0 1
        0 0 0 0 0
        1 0 0 0 0
    ])
    partial = sparse([
        0 0 0 0 1
        0 0 1 0 0
        1 0 0 0 0
    ])
    neg = sparse([
        0 0 1 1 0
        1 1 0 0 1
        0 0 0 0 0
    ])

    # With indices.
    for v in [
        gc((@GraphData A{Float64}), [1 => [5 => 100], 3 => [1 => 200]]),
        gc((@GraphData A{:bin}), [1 => [5], 3 => [1]]),
    ]
        # Check index space.
        @test @check_list_refs v :item (3, 5)
        @failswith(
            (@check_list_refs v :item (2, 5)),
            BlueprintCheckFailure("Invalid 'item' edge index in 'v'. \
                                   Index '3' does not fall within the valid range 1:2.")
        )
        # Check against a template.
        @test @check_list_refs v :item template(partial)
        @failswith(
            (@check_list_refs v :item template(neg)),
            BlueprintCheckFailure("Invalid 'item' edge index in 'v': (1, 5). \
                                   Valid edges target indices \
                                   for source 1 in this template are:\n  [3, 4]")
        )
    end

    # No matching targets.
    v = gc((@GraphData A{Float64}), [3 => [5 => 100]])
    @failswith(
        (@check_list_refs v :item template(neg)),
        BlueprintCheckFailure("Invalid 'item' edge index in 'v': (3, 5). \
                               This template allows no valid edge targets indices \
                               for source 3.")
    )

    # Cannot check densely against a 2D template.
    @argfails(
        (@check_list_refs v :item template(full) dense),
        "Dense adjacency lists checking is unimplemented yet."
    )

    # Empty space.
    @failswith(
        (@check_list_refs v :item 0),
        BlueprintCheckFailure("No possible valid edge index in 'v' like (3, 5): \
                               the reference space for 'item' is empty.")
    )

    # With labels.
    for v in [
        gc((@GraphData A{Float64}), [:a => [:e => 100], :c => [:a => 200]]),
        gc((@GraphData A{:bin}), [:a => [:e], :c => [:a]]),
    ]
        # Check labels space.
        @test @check_list_refs v :item (part_index, full_index)
        @failswith(
            (@check_list_refs v :item (full_index, part_index)),
            BlueprintCheckFailure("Invalid 'item' edge label in 'v'. \
                                   Expected either :a, :b or :c, got instead: :e.")
        )
        # Check against a template.
        @test @check_list_refs v :item (part_index, full_index) template(partial)
        # Implicit same index for source/target.
        @test @check_list_refs v :item full_index template(partial)
        @failswith(
            (@check_list_refs v :item full_index template(neg)),
            BlueprintCheckFailure("Invalid 'item' edge label in 'v': (:a, :e). \
                                   Valid edges target labels for source :a \
                                   in this template are:\n  [:c, :d]")
        )
    end

    # No matching targets.
    v = gc((@GraphData A{Float64}), [:c => [:e => 100]])
    @failswith(
        (@check_list_refs v :item full_index template(neg)),
        BlueprintCheckFailure("Invalid 'item' edge label in 'v': (:c, :e). \
                               This template allows no valid edge targets labels \
                               for source :c.")
    )

    # Cannot check densely against a 2D template.
    @argfails(
        (@check_list_refs v :item full_index template(full) dense),
        "Dense adjacency lists checking is unimplemented yet."
    )

    # Empty space.
    @failswith(
        (@check_list_refs v :item Dict{Symbol,Int64}()),
        BlueprintCheckFailure("No possible valid edge label in 'v' like (:c, :e): \
                               the reference space for 'item' is empty.")
    )

    # Indices space automatically inferred from labels index.
    v = gc((@GraphData A{Float64}), [3 => [5 => 100]])
    @test @check_list_refs v :item full_index

    # ======================================================================================
    # Sugar for checking the variable only if they have the adequate type.

    #---------------------------------------------------------------------------------------
    # Symbol.

    input = :a
    @test @check_if_symbol input :a
    @test @check_if_symbol input a
    @test @check_if_symbol input (:a,)
    @test @check_if_symbol input (a,)
    @test @check_if_symbol input (a, b)
    @test @check_if_symbol input (:a, :b)
    @failswith((@check_if_symbol input (:x, :y)), BlueprintCheckFailure)

    # Dont' check if not a symbol.
    input = 5
    @test !@check_if_symbol input :a # (no error thrown, but the check returns false)

    #---------------------------------------------------------------------------------------
    # Vector size.

    input = [1, 2, 3]
    n = 3
    @test @check_size_if_vector input 3
    @test @check_size_if_vector input n
    @test @check_size_if_vector input Any
    @test @check_size_if_vector input (3,)
    @test @check_size_if_vector input (n,)
    @test @check_size_if_vector input (Any,)
    @failswith((@check_size_if_vector input 4), BlueprintCheckFailure)

    # Don't check 1D size if not a vector.
    input = 5
    @test !@check_size_if_vector input 8 # (no error thrown, but the check returns false)
    input = [0 0; 0 1]
    @test !@check_size_if_vector input 8

    #---------------------------------------------------------------------------------------
    # Matrix size.

    input = [0 0; 0 1]
    m, n = mn = (2, 2)
    @test @check_size_if_matrix input (2, 2)
    @test @check_size_if_matrix input (m, n)
    @test @check_size_if_matrix input (Any, n)
    @test @check_size_if_matrix input (n, Any)
    @test @check_size_if_matrix input mn
    @failswith((@check_size_if_matrix input (3, 3)), BlueprintCheckFailure)

    # Don't check 2D size if not a matrix.
    input = 5
    @test !@check_size_if_matrix input (8, 9)
    input = [1, 2, 3]
    @test !@check_size_if_matrix input (8, 9)

    #---------------------------------------------------------------------------------------
    # Sparse arrays.

    template = sparse([0, 0, 1, 0, 1, 0, 1])
    input = sparse([0, 0, 4, 0, 5, 0, 6])
    @test @check_template_if_sparse input template :item
    input[1] = 7
    @failswith((@check_template_if_sparse input template :item), BlueprintCheckFailure)

    # Don't check if not sparse.
    input = 5
    @test !@check_template_if_sparse input template :item
    input = [1, 2]
    @test !@check_template_if_sparse input template :item
    template = sparse([
        0 1 1
        1 0 0
        0 1 0
    ])
    input = sparse([
        0 4 5
        6 0 0
        0 7 0
    ])
    @test @check_template_if_sparse input template :item
    input[1, 1] = 8
    @failswith((@check_template_if_sparse input template :item), BlueprintCheckFailure)
    input = 5
    @test !@check_template_if_sparse input template :item
    input = [0 0; 0 0]
    @test !@check_template_if_sparse input template :item

    #---------------------------------------------------------------------------------------
    # Maps.

    input = gc((@GraphData K{Float64}), [1 => 5, 3 => 8])
    @test @check_refs_if_list input :item 5
    @failswith((@check_refs_if_list input :item 2), BlueprintCheckFailure)

    input = gc((@GraphData K{Float64}), [1 => 5, 2 => 8])
    @test @check_refs_if_list input :item 2 dense
    @failswith((@check_refs_if_list input :item 3 dense), BlueprintCheckFailure)

    input = gc((@GraphData K{:bin}), [1, 3])
    @test @check_refs_if_list input :item 5
    @failswith((@check_refs_if_list input :item 2), BlueprintCheckFailure)

    input = gc((@GraphData K{:bin}), [1, 2])
    @test @check_refs_if_list input :item 2
    @failswith((@check_refs_if_list input :item 3 dense), ArgumentError)

    # Don't check if not a mapping.
    input = 5
    @test !@check_refs_if_list input :item 0
    input = [5, 8]
    @test !@check_refs_if_list input :item 0

    #---------------------------------------------------------------------------------------
    # Adjacency lists.

    input = gc((@GraphData A{Float64}), [1 => [3 => 8]])
    @test @check_refs_if_list input :item (5, 5)
    @failswith((@check_refs_if_list input :item (2, 2)), BlueprintCheckFailure)

    input = gc((@GraphData A{:bin}), [1 => [3]])
    @test @check_refs_if_list input :item (5, 5)
    @failswith((@check_refs_if_list input :item (2, 2)), BlueprintCheckFailure)

    # Don't check if not an adjacency list.
    input = 5
    @test !@check_refs_if_list input :item (0, 0)
    input = [5, 8]
    @test !@check_refs_if_list input :item (0, 0)
    input = "[5, 8]"
    @test !@check_refs_if_list input :item (0, 0)

end

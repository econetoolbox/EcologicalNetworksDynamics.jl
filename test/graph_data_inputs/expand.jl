@testset "Graph data expansion." begin

    # ======================================================================================
    # Symbols.

    input = :a
    res = @expand_symbol(input, a => 4 + 5, b => "nope", c => unevaluated)
    res = @expand_symbol(input, :a => 4 + 5, :b => "nope", :c => unevaluated)
    @test res == 9

    # Use sophisticated expressions if needed.
    res = @expand_symbol(
        input,
        a => begin
            temp = 5
            res = "capturing outer variable: $(repr(input))"
            res
        end,
        b => 0,
        c => 0,
    )
    @test res == "capturing outer variable: :a"
    # Still, leave this scope clean.
    @test !(@isdefined temp)

    # Incorrect uses.
    @failswith(@expand_symbol(input, a), MethodError, expansion)
    @xargfails(
        @expand_symbol(input, 4 + 5),
        [
            "Invalid @expand_symbol macro use at",
            "Expected `symbol => expression` pairs. Got :(4 + 5).",
        ]
    )
    @xargfails(
        @expand_symbol(input, (4 + 5) => 8),
        [
            "Invalid @expand_symbol macro use at",
            "Expected `symbol => expression` pairs. Got :(4 + 5 => 8).",
        ]
    )
    input = :wrong
    @argfails( # Invoker failed to meet assumptions.
        @expand_symbol(input, a => 5),
        "⚠ Incorrectly checked symbol for input: :wrong. \
         This is a bug in the package. \
         Consider reporting if you can reproduce with a minimal example."
    )

    # ======================================================================================
    # Arrays.

    #---------------------------------------------------------------------------------------
    # Scalar to dense array.

    @test to_size(2, 3) == [2, 2, 2]
    @test to_size(2, (3, 4)) == [
        2 2 2 2
        2 2 2 2
        2 2 2 2
    ]

    #---------------------------------------------------------------------------------------
    # Scalar to sparse array.

    # Vector template.
    template = sparse([0, 0, 1, 0, 1, 0, 1])
    @test to_template(5, template) == sparse([0, 0, 5, 0, 5, 0, 5])

    # Stored zero in the template are still considered non-missing entries.
    template[3] -= 1 # So this does not "void" entry [3].
    @test to_template(5, template) == sparse([0, 0, 5, 0, 5, 0, 5]) # Same.

    # Matrix template.
    template = sparse([
        0 1 1
        1 0 0
        0 1 0
    ])
    @test to_template(5, template) == sparse([
        0 5 5
        5 0 0
        0 5 0
    ])

    # Same "non-missing" logic here.
    template[1, 2] -= 1
    @test to_template(5, template) == sparse([
        0 5 5 # <- Still here.
        5 0 0
        0 5 0
    ])

    #---------------------------------------------------------------------------------------
    # Vector to sparse vector.

    template = sparse([0, 0, 1, 0, 1, 0, 1])
    input = [4, 5, 6]
    @test sparse_from_values(input, template) == sparse([0, 0, 4, 0, 5, 0, 6])
    template[3] -= 1 # Silent non-missing zero.
    @test sparse_from_values(input, template) == sparse([0, 0, 4, 0, 5, 0, 6]) # Unchanged.
    @argfails(
        sparse_from_values([4, 6], template),
        "Not enough values provided (2) to fill the given template (3 required)."
    )
    @argfails(
        sparse_from_values([4, 5, 6, 7], template),
        "Too many values provided (4) to fill the given template (3 required)."
    )

    #---------------------------------------------------------------------------------------
    # Row/Column-wise vector expansion.

    input = [4, 5, 6]
    @test from_row(input, 2) == [
        4 5 6
        4 5 6
    ]
    @test from_col(input, 2) == [
        4 4
        5 5
        6 6
    ]

    template = sparse([
        0 1 1
        1 0 0
        0 1 0
    ])
    input = [4, 5, 6]
    @test from_row(input, template) == sparse([
        0 5 6
        4 0 0
        0 5 0
    ])
    @test from_col(input, template) == sparse([
        0 4 4
        5 0 0
        0 6 0
    ])
    template[1, 2] -= 1 # Silent non-missing zero.
    @test from_row(input, template) == sparse([ # Unchanged.
        0 5 6
        4 0 0
        0 5 0
    ])
    @test from_col(input, template) == sparse([ # Unchanged.
        0 4 4
        5 0 0
        0 6 0
    ])
    @argfails(
        from_row([4, 5], template),
        "Row size mismatch: 2 values input, but 3 columns in template.",
    )
    @argfails(
        from_col([4, 5, 6, 7], template),
        "Column size mismatch: 4 values input, but 3 rows in template.",
    )

    #---------------------------------------------------------------------------------------
    # Vectors from key-values maps.

    gc = GraphDataInputs.graphdataconvert
    index = Dict(Symbol(c) => i for (i, c) in enumerate("abc"))

    # To sparse data.
    input = gc((@GraphData K{Float64}), [3 => 8, 1 => 7])
    @test to_sparse_vector(input, 3) == sparse([7.0, 0, 8.0])

    input = gc((@GraphData K{Float64}), [:c => 8, :a => 7])
    @test to_sparse_vector(input, index) == sparse([7.0, 0, 8.0])

    input = gc((@GraphData K{:bin}), [3, 1])
    @test to_sparse_vector(input, 3) == sparse([true, false, true])

    input = gc((@GraphData K{:bin}), [:c, :a])
    @test to_sparse_vector(input, index) == sparse([true, false, true])

    # To dense data (watch not to miss data).
    input = gc((@GraphData K{Float64}), [3 => 8, 1 => 7, 2 => 9])
    @test to_dense_vector(input) == [7.0, 9.0, 8.0]

    input = gc((@GraphData K{Float64}), [:c => 8, :a => 7, :b => 9])
    @test to_dense_vector(input, index) == [7.0, 9.0, 8.0]

    input = Dict(:c => 3, :a => 1, :b => 2)
    @test to_dense_refs(input) == [:a, :b, :c]

    #---------------------------------------------------------------------------------------
    # Matrices from adjacency lists.

    # To dense data (watch not to miss data).
    small, large =
        (Dict(Symbol(c) => i for (i, c) in enumerate(letters)) for letters in ("ab", "ABC"))

    input = gc(
        (@GraphData A{Float64}),
        [1 => [3 => 5, 1 => 8, 2 => 4], 2 => [2 => 9, 3 => 7, 1 => 3]],
    )
    @test to_dense_matrix(input) == [
        8 4 5
        3 9 7
    ]

    input = gc(
        (@GraphData A{Float64}),
        [:a => [:C => 5, :A => 8, :B => 4], :b => [:B => 9, :C => 7, :A => 3]],
    )
    @test to_dense_matrix(input, small, large) == [
        8 4 5
        3 9 7
    ]

    # To sparse data.
    small, large = (
        Dict(Symbol(c) => i for (i, c) in enumerate(letters)) for
        letters in ("abc", "ABCDE")
    )

    input = gc((@GraphData A{Int64}), [3 => [5 => 7], 2 => [3 => 8]])
    @test to_sparse_matrix(input, 3, 5) == sparse([
        0 0 0 0 0
        0 0 8 0 0
        0 0 0 0 7
    ])

    input = gc((@GraphData A{Int64}), [:c => [:E => 7], :b => [:C => 8]])
    @test to_sparse_matrix(input, small, large) == sparse([
        0 0 0 0 0
        0 0 8 0 0
        0 0 0 0 7
    ])

    input = gc((@GraphData A{:bin}), [3 => [5], 2 => [3]])
    @test to_sparse_matrix(input, 3, 5) == sparse([
        0 0 0 0 0
        0 0 1 0 0
        0 0 0 0 1
    ])

    input = gc((@GraphData A{:bin}), [:c => [:E], :b => [:C]])
    @test to_sparse_matrix(input, small, large) == sparse([
        0 0 0 0 0
        0 0 1 0 0
        0 0 0 0 1
    ])

    # ======================================================================================
    # Sugar for rebinding the variables in place.

    #---------------------------------------------------------------------------------------
    # From symbols.

    input = :a
    @expand_if_symbol(input, a => 5, b => 8)
    @test input == 5 # Changed.

    input = 1 # Not a symbol.
    @expand_if_symbol(input, a => 5, b => 8)
    @test input == 1 # Unchanged.

    #---------------------------------------------------------------------------------------
    # From scalars.

    input = 5
    @to_size_if_scalar(Real, input, 3)
    @test input == [5, 5, 5]

    input = [8, 8] # Not a scalar.
    @to_size_if_scalar(Real, input, 3)
    @test input == [8, 8]

    input = 5
    template = sparse([0, 0, 1, 0, 1, 0, 1])
    @to_template_if_scalar(Real, input, template)
    @test input == sparse([0, 0, 5, 0, 5, 0, 5])

    input = "not a scalar"
    @to_template_if_scalar(Real, input, template)
    @test input == "not a scalar"

    #---------------------------------------------------------------------------------------
    # From vectors.

    input = [4, 5, 6]
    @sparse_from_values_if_vector(input, template)
    @test input == sparse([0, 0, 4, 0, 5, 0, 6])

    input = "not a vector"
    @sparse_from_values_if_vector(input, template)
    @test input == "not a vector"

    input = [4, 5, 6]
    @expand_from_row_if_vector(input, 2)
    @test input == [
        4 5 6
        4 5 6
    ]

    input = "not a vector"
    @expand_from_row_if_vector(input, template)
    @test input == "not a vector"

    input = [4, 5, 6]
    @expand_from_col_if_vector(input, 2)
    @test input == [
        4 4
        5 5
        6 6
    ]

    input = "not a vector"
    @expand_from_col_if_vector(input, template)
    @test input == "not a vector"

    #---------------------------------------------------------------------------------------
    # From maps and adjacency lists.

    # Dense vector.
    input = gc((@GraphData K{Float64}), [1 => 5, 3 => 13, 2 => 8])
    @to_dense_vector_if_map input small
    @test input == [5.0, 8.0, 13.0]

    input = "not a map"
    @to_dense_vector_if_map input small
    @test input == "not a map"

    # Sparse vector.
    input = gc((@GraphData K{Float64}), [1 => 5, 3 => 13, 2 => 8])
    @to_sparse_vector_if_map input large
    @test input == sparse([5.0, 8.0, 13.0, 0, 0])

    input = gc((@GraphData K{:bin}), [1, 3, 2])
    @to_sparse_vector_if_map input large
    @test input == sparse([1, 1, 1, 0, 0])

    input = "not a map"
    @to_sparse_vector_if_map input large
    @test input == "not a map"

    # Sparse matrix.
    input = gc((@GraphData A{Float64}), [1 => [5 => 8], 3 => [3 => 5]])
    @to_sparse_matrix_if_adjacency input small large
    @test input == sparse([
        0 0 0 0 8.0
        0 0 0 0 0
        0 0 5.0 0 0
    ])

    input = gc((@GraphData A{:bin}), [1 => [5], 3 => [3]])
    @to_sparse_matrix_if_adjacency input small large
    @test input == sparse([
        0 0 0 0 1
        0 0 0 0 0
        0 0 1 0 0
    ])

    input = "not a map"
    @to_sparse_matrix_if_adjacency input small large
    @test input == "not a map"

    # Dense matrix.
    small, large =
        (Dict(Symbol(c) => i for (i, c) in enumerate(letters)) for letters in ("ab", "ABC"))

    input = gc(
        (@GraphData A{Float64}),
        [1 => [1 => 8, 2 => 5, 3 => 4], 2 => [2 => 7, 1 => 9, 3 => 2]],
    )
    @to_dense_matrix_if_adjacency input small large
    @test input == [
        8 5 4
        9 7 2
    ]

    input = "not a map"
    @to_dense_matrix_if_adjacency input small large
    @test input == "not a map"

end

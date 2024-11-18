# Expansion utils: expand checked input to final size.
# These cannot fail as they would abort the system's `expand!` methods.

# ==========================================================================================
# Assuming the input is an *expected* symbol,
# Expand symbol into a full-fledged value.
macro expand_symbol(var::Symbol, pairs::Expr...)
    @defloc
    expand_symbol(loc, var, pairs)
end
function expand_symbol(loc, var, pairs)
    symbols = []
    exprs = []
    err(p) = argerr("Invalid @expand_symbol macro use at $loc.\n\
                     Expected `symbol => expression` pairs. \
                     Got $(repr(p)).")
    for p in pairs
        @capture(p, s_ => x_)
        isnothing(s) && err(p)
        if s isa Symbol
            push!(symbols, s)
        elseif s isa QuoteNode && s.value isa Symbol
            push!(symbols, s.value)
        else
            err(p)
        end
        push!(exprs, quote
            let # Isolate expressions into their own hard scope.
                $x
            end
        end)
    end
    varsymbol = Meta.quot(var)
    symbols = Meta.quot.(symbols)
    var = esc(var)
    exprs = esc.(exprs)
    res = :(
        if $var == $(first(symbols))
            $(first(exprs))
        else
            argerr("⚠ Incorrectly checked symbol for $($varsymbol): $(repr($var)). \
                    This is a bug in the package. \
                    Consider reporting if you can reproduce with a minimal example.")
        end
    )
    # Add as many elseif clauses as needed.
    for (s, expr) in Iterators.drop(zip(symbols, exprs), 1)
        res.args[3] = Expr(:elseif, :($var == $s), expr, res.args[3])
    end
    res
end
export @expand_symbol

# ==========================================================================================
# Assuming the input is a scalar, expand to the desired size.

to_size(scalar, s) = fill(scalar, s)
to_size(scalar, s::Integer) = fill(scalar, (s,))
export to_size

#-------------------------------------------------------------------------------------------
# Assuming the input is a scalar, expand to the desired template.

function to_template(scalar, template::AbstractSparseVector)
    T = typeof(scalar)
    res = spzeros(T, size(template))
    for i in findnz(template)[1]
        res[i] = scalar
    end
    res
end

function to_template(scalar, template::AbstractSparseMatrix)
    T = typeof(scalar)
    res = spzeros(T, size(template))
    is, js = findnz(template)
    for (i, j) in zip(is, js)
        res[i, j] = scalar
    end
    res
end

export to_template

# ==========================================================================================
# Assuming the input is a vector with correct size,
# expand to the given template using its non-missing entries.

function sparse_from_values(values, template::AbstractSparseVector{T}) where {T}
    res = spzeros(T, size(template))
    entries, = findnz(template)
    v, e = length.((values, entries))
    v == e || argerr("$(v < e ? "Not enough" : "Too many") values provided ($v) \
                      to fill the given template ($e required).")
    for (i, v) in zip(entries, values)
        res[i] = v
    end
    res
end
export sparse_from_values

#-------------------------------------------------------------------------------------------
# Assuming the input is a vector with correct size,
# expand to the given size using its value as rows or columns.

from_row(row, n_rows::Integer) = repeat(transpose(row), n_rows)
from_col(col, n_cols::Integer) = repeat(col, 1, n_cols)

# Same given a sparse template.
function from_row(row, template::AbstractSparseMatrix{T}) where {T}
    r, t = length(row), size(template, 2)
    r == t || argerr("Row size mismatch: $r value$(s(r)) input, \
                      but $t column$(s(t)) in template.")
    res = spzeros(T, size(template))
    for (i, j, _) in zip(findnz(template)...)
        res[i, j] = row[j]
    end
    res
end
export from_row

function from_col(col, template::AbstractSparseMatrix{T}) where {T}
    c, t = length(col), size(template, 2)
    c == t || argerr("Column size mismatch: $c value$(s(c)) input, \
                      but $t row$(s(t)) in template.")
    res = spzeros(T, size(template))
    for (i, j, _) in zip(findnz(template)...)
        res[i, j] = col[i]
    end
    res
end
export from_col

s(n) = n == 1 ? "" : "s"

# ==========================================================================================
# Assuming the input is a correcly checked map,
# expand to a vector or a sparse vector.
# This may require a label-to-indices mapping referred to as "index" (yup, confusing).
# TODO: abstract over map/adjacency with in the same fashion as for checking?

# Assuming all indices have been given.
function to_dense_vector(map::AbstractMap{Int64,T}) where {T}
    res = Vector{T}(undef, length(map))
    for (i, value) in map
        res[i] = value
    end
    res
end

function to_dense_vector(map::AbstractMap{Symbol,T}, index) where {T}
    res = Vector{T}(undef, length(map))
    for (key, value) in map
        i = index[key]
        res[i] = value
    end
    res
end

export to_dense_vector

# Assuming input is a dense index.
function to_dense_refs(index::AbstractDict{Symbol,Int})
    refs = Vector{Symbol}(undef, length(index))
    for (ref, i) in index
        refs[i] = ref
    end
    refs
end
export to_dense_refs

# Assuming all indices are valid.
function to_sparse_vector(map::AbstractMap{Int64,T}, n::Int64) where {T}
    res = spzeros(T, n)
    for (i, value) in map
        res[i] = value
    end
    res
end

function to_sparse_vector(map::AbstractMap{Symbol,T}, index) where {T}
    res = spzeros(T, length(index))
    for (key, value) in map
        i = index[key]
        res[i] = value
    end
    res
end

function to_sparse_vector(map::AbstractBinMap{Int64}, n::Int64)
    res = spzeros(Bool, n)
    for i in map
        res[i] = true
    end
    res
end

function to_sparse_vector(map::AbstractBinMap{Symbol}, index)
    res = spzeros(Bool, length(index))
    for key in map
        i = index[key]
        res[i] = true
    end
    res
end

export to_sparse_vector

# Accommodate slight signature variations in case an index is always used.
function to_dense_vector(map::AbstractMap{Int64,T}, index) where {T}
    m, i = length.((map, index))
    m == i || argerr("Cannot produce a dense vector with $m values and $i references.")
    to_dense_vector(map)
end
to_sparse_vector(map::AbstractMap{Int64,T}, index) where {T} =
    to_sparse_vector(map, length(index))
to_sparse_vector(map::AbstractBinMap{Int64}, index) = to_sparse_vector(map, length(index))

#-------------------------------------------------------------------------------------------
# Assuming the input is a correctly checked adjacency list,
# expand to a dense or sparse matrix.
# This may require a label-to-indices mapping referred to as "index" (yup, confusing).

# Assuming all indices have been given.
function to_dense_matrix(adj::AbstractAdjacency{Int64,T}) where {T}
    res = Matrix{T}(undef, (length(adj), length(last(first(adj)))))
    for (i, list) in adj
        for (j, value) in list
            res[i, j] = value
        end
    end
    res
end

function to_dense_matrix(adj::AbstractAdjacency{Symbol,T}, i_index, j_index) where {T}
    res = Matrix{T}(undef, (length(adj), length(last(first(adj)))))
    for (ikey, list) in adj
        for (jkey, value) in list
            i = i_index[ikey]
            j = j_index[jkey]
            res[i, j] = value
        end
    end
    res
end

export to_dense_matrix

function to_sparse_matrix(adj::AbstractAdjacency{Int64,T}, n::Int64, m::Int64) where {T}
    res = spzeros(T, (n, m))
    for (i, list) in adj
        for (j, value) in list
            res[i, j] = value
        end
    end
    res
end

function to_sparse_matrix(adj::AbstractAdjacency{Symbol,T}, i_index, j_index) where {T}
    res = spzeros(T, (length(i_index), length(j_index)))
    for (ikey, list) in adj
        i = i_index[ikey]
        for (jkey, value) in list
            j = j_index[jkey]
            res[i, j] = value
        end
    end
    res
end

function to_sparse_matrix(adj::AbstractBinAdjacency{Int64}, n::Int64, m::Int64)
    res = spzeros(Bool, (n, m))
    for (i, list) in adj
        for j in list
            res[i, j] = true
        end
    end
    res
end

function to_sparse_matrix(adj::AbstractBinAdjacency{Symbol}, i_index, j_index)
    res = spzeros(Bool, (length(i_index), length(j_index)))
    for (ikey, list) in adj
        i = i_index[ikey]
        for jkey in list
            j = j_index[jkey]
            res[i, j] = true
        end
    end
    res
end

export to_sparse_matrix

# Accommodate slight signature variations in case an index is always used.
function to_dense_matrix(adj::AbstractAdjacency{Int64,T}, i_index, j_index) where {T}
    m, i = length.((adj, i_index))
    n, j = length.((last(first(adj)), j_index))
    m == i || argerr(
        "Cannot produce a dense matrix with $m outer values and $i outer references.",
    )
    n == j || argerr(
        "Cannot produce a dense matrix with $n inner values and $j inner references.",
    )
    to_dense_matrix(adj)
end
to_sparse_matrix(map::AbstractAdjacency{Int64,T}, i_index, j_index) where {T} =
    to_sparse_matrix(map, length(i_index), length(j_index))
to_sparse_matrix(map::AbstractBinAdjacency{Int64}, i_index, j_index) =
    to_sparse_matrix(map, length(i_index), length(j_index))

# ==========================================================================================
# Ease use.

# Sugar for this awkward pattern:
#   var isa Symbol && (var = @expand_symbol(var, ...))
macro expand_if_symbol(var::Symbol, pairs::Expr...)
    @defloc
    build = expand_symbol(loc, var, pairs)
    var = esc(var)
    quote
        $var isa Symbol && ($var = $build)
    end
end
export @expand_if_symbol

# Sugar for this awkward pattern:
#    var isa Scalar && (var = to_size(var, ...))
# It must be specified what the 'Scalar' means, not sure how/whether to avoid that.
macro to_size_if_scalar(Scalar, var::Symbol, size)
    Scalar, var, size = esc.((Scalar, var, size))
    quote
        $var isa $Scalar && ($var = to_size($var, $size))
    end
end
export @to_size_if_scalar

# Same for to_template.
macro to_template_if_scalar(Scalar, var::Symbol, template)
    Scalar, var, template = esc.((Scalar, var, template))
    quote
        $var isa $Scalar && ($var = to_template($var, $template))
    end
end
export @to_template_if_scalar

# Sugar for this awkward pattern:
#   var isa AbstractVector && (var = sparse_from_values(var, ...))
macro sparse_from_values_if_vector(var::Symbol, template)
    var, template = esc.((var, template))
    quote
        $var isa AbstractVector && ($var = sparse_from_values($var, $template))
    end
end
export @sparse_from_values_if_vector

#-------------------------------------------------------------------------------------------
# Same for from_row/from_col.

macro expand_from_row_if_vector(var::Symbol, parm)
    var, parm = esc.((var, parm))
    quote
        $var isa AbstractVector && ($var = from_row($var, $parm))
    end
end
export @expand_from_row_if_vector

macro expand_from_col_if_vector(var::Symbol, parm)
    var, parm = esc.((var, parm))
    quote
        $var isa AbstractVector && ($var = from_col($var, $parm))
    end
end
export @expand_from_col_if_vector

#-------------------------------------------------------------------------------------------
# Same for maps and adjacency lists.
macro to_dense_vector_if_map(var::Symbol, index)
    var, index = esc.((var, index))
    quote
        $var isa Union{AbstractDict,AbstractSet} && ($var = to_dense_vector($var, $index))
    end
end
export @to_dense_vector_if_map

macro to_sparse_vector_if_map(var::Symbol, index)
    var, index = esc.((var, index))
    quote
        $var isa Union{AbstractDict,AbstractSet} && ($var = to_sparse_vector($var, $index))
    end
end
export @to_sparse_vector_if_map

macro to_dense_matrix_if_adjacency(var::Symbol, i_index, j_index)
    var, i_index, j_index = esc.((var, i_index, j_index))
    quote
        $var isa
        Union{AbstractDict{<:Any,<:AbstractDict},AbstractDict{<:Any,<:AbstractSet}} &&
            ($var = to_dense_matrix($var, $i_index, $j_index))
    end
end
export @to_dense_matrix_if_adjacency

macro to_sparse_matrix_if_adjacency(var::Symbol, i_index, j_index)
    var, i_index, j_index = esc.((var, i_index, j_index))
    quote
        $var isa
        Union{AbstractDict{<:Any,<:AbstractDict},AbstractDict{<:Any,<:AbstractSet}} &&
            ($var = to_sparse_matrix($var, $i_index, $j_index))
    end
end
export @to_sparse_matrix_if_adjacency

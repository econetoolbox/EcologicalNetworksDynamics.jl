# Checking utils: verify input against an actual model value.

# ==========================================================================================
# Check every value as a scalar, providing a Function(value, index) callback
# throwing on invalid values.
check_values(check, values; items = items) =
    for (ref, value) in items(values)
        check(value, ref)
    end
check_nodes(c, n) = check_values(c, n; items = node_items)
check_edges(c, n) = check_values(c, n; items = edge_items)
export check_nodes, check_edges, check_values

# ==========================================================================================
# Assuming the input is a symbol,
# check that it is one of the expected symbols,
# emitting a useful error message on invalid symbol
# with the expected list of valid symbols.
macro check_symbol(var::Symbol, list)
    @defloc
    _check_symbol(loc, var, list)
end
function _check_symbol(loc, var, list)
    symbols = []
    inputerr() = argerr("Invalid @check_symbol macro use at $loc.\n\
                         Expected a list of symbols. \
                         Got $(repr(list)).")
    list isa Expr || (list = :(($list,)))
    list.head in (:tuple, :vect) || inputerr()
    for s in list.args
        if s isa Symbol
            push!(symbols, s)
        elseif s isa QuoteNode && s.value isa Symbol
            # Allow `:symbol` instead of just `symbol` for less confusion.
            push!(symbols, s.value)
        else
            inputerr()
        end
    end
    exp =
        length(symbols) == 1 ? "$(repr(first(symbols)))" :
        "either $(join(map(repr, symbols), ", ", " or "))"
    symbols = Meta.quot.(symbols)
    symbols = Expr(:tuple, symbols...)
    varsymbol = Meta.quot(var)
    var = esc(var)
    quote
        $var in $symbols ||
            checkfails("Invalid symbol received for '$($varsymbol)': $(repr($var)). \
                        Expected $($exp) instead.")
        true # For use within the @test macro.
    end
end
export @check_symbol

# ==========================================================================================
# Assuming the input is an array, check its size.

# Check value size agains expectation.
function check_size(varsymbol, value, expected_size::Tuple)
    actual_size = size(value)
    if !same_size(actual_size, expected_size)
        checkfails("Invalid size for parameter '$varsymbol': \
                    expected $expected_size, got $actual_size.")
    end
    true # For use within the @test macro.
end
check_size(s, v, e::Integer) = check_size(s, v, (e,))
check_size(s, v, ::Type{Any}) = check_size(s, v, (Any,))

# This being a macro is useful so the variable name can be reported one check failure.
macro check_size(var::Symbol, size)
    _check_size(var, size)
end
function _check_size(var, size)
    varsymbol = Meta.quot(var)
    size = esc(to_tuple(size))
    value = esc(var)
    quote
        check_size($varsymbol, $value, $size)
    end
end
export @check_size

# Transform scalar size macro input to unit tuple:
# so that eg. `@check_size a s` means `@check_size a (s,)`.
function to_tuple(size)
    # (Allow plain variables names, assuming they evaluate to a correct size.)
    size isa Symbol && size != :Any && return size
    (size isa Expr && size.head == :tuple) ? size : :(($size,))
end

# Use `Any` in the expected size to "any size" in the given dimension:
# so that eg. `@check_size m (Any, s)` only checks that the number of columns is s.
function same_size(actual::Tuple, expected::Tuple)
    length(actual) == length(expected) || return false
    for (a, e) in zip(actual, expected)
        e == Any && continue
        a == e || return false
    end
    true
end

# ==========================================================================================
# Assuming the input is a sparse array, check its template against a model template.
# No missing entry in the template can be non-missing in the value,
# The semantic confusion between 'missing' and 'zero' makes the intuition tricky here.
# Let's distinguish between:
#   - "·" : a "missing" value *not stored* in the collection (and typically meaning "zero").
#   - "0" : an actual "zero" value *stored* in the collection.
#   - "N" : an actual "non-zero" value *stored* in the collection.
# Here is the checking matrix, with template entries as rows and checked entries as columns:
# (actual\expected)
#
#   a\e  ·  0  N
#    ·   ✓  🗙  🗙  <- The check only fails on unexpected stored entries.
#    0   ✓  ✓  ✓
#    N   ✓  ✓  ✓
#
# Which simplifies into a simple missing / non-missing dichotomy:
#
#   a\e · 0N  (missing/non-missing)
#    ·  ✓ 🗙
#    0N ✓ ✓
#       ^
#       Automatically set to stored zero.

# Check value against a sparse template,
# the "item" of the template specifies its meaning
# by naming the corresponding node or edge object type,
# helpful to produce useful errors.
function check_template(varsymbol, value, template::AbstractSparseVector, item)
    check_size(varsymbol, value, size(template))
    nonmiss = Set(findnz(template)[1])
    for (i, v) in zip(findnz(value)...)
        i in nonmiss || checkfails("Non-missing value found for '$varsymbol' \
                                    at node index [$i] ($v), \
                                    but the template for '$item' \
                                    only allows values at the following indices:\n  \
                                    $(findnz(template)[1])")
    end
    true # For use within the @test macro.
end
function check_template(varsymbol, value, template::AbstractSparseMatrix, item)
    check_size(varsymbol, value, size(template))
    nonmiss = Set(zip(findnz(template)[1:2]...))
    for (i, j, v) in zip(findnz(value)...)
        (i, j) in nonmiss && continue
        checkfails("Non-missing value found for '$varsymbol' \
                    at edge index [$i, $j] ($v), \
                    but the template for '$item' \
                    only allows values at the following indices:\n  \
                    $([ij for ij in zip(findnz(template)[1:2]...)])")
    end
    true # For use within the @test macro.
end

macro check_template(varname::Symbol, template, item)
    varsymbol = Meta.quot(varname)
    template = esc(template)
    value = esc(varname)
    quote
        check_template($varsymbol, $value, $template, $item)
    end
end
export @check_template

# ==========================================================================================
# Assuming the input is a key-value map: check that all references are defined,
# possibly against a sparse template.
# This results in quite a binary cartesian product of expected checking behaviours:
# (binary, values) × (integer, labels) × (nodes, edges)
#                  × (non-templated, templated) × (dense, sparse) × ...
# One snag in particular: on integer × template, the reference size becomes superfluous,
#                 but on:     labels × template, the reference index is still required.
# This results in the number of parameters not being consistent
# for every method/macro combination.
# Try to handle the whole product smoothly by leveraging julia's multiple dispatch.
# Then resolt to porcelain snags to accommodate the interface.
# In this chunk of code:
#   list: is either a map or an adjacency list, binary or not.
#   ref: is either i, (i, j), :a or (:a, :b).
#   space: is a specification of the set of all possible references:
#          Int64, (Int64, Int64), Index or (Index, Index).
#          So the space is *also* an index to convert labels to integers.

#-------------------------------------------------------------------------------------------
# Check that the given value is a valid (dense) {ref -> indice} index.
function check_index(index::AbstractDict{Symbol,Int})
    n = length(index)
    notfound = OrderedSet(1:n)
    for (ref, i) in index
        1 <= i <= n || argerr("Invalid index: received $n reference$(n > 1 ? "s" : "") \
                               but one of them is [$i] ($(repr(ref))).")
        if i in notfound
            pop!(notfound, i)
        end
    end
    for i in notfound
        argerr("Invalid index: no reference given for index [$i].")
    end
end
export check_index

#-------------------------------------------------------------------------------------------
# Check references against a general reference space.

# The most abstract entry point into checking refs, with subcalls to other checking utils.
function check_list_refs(
    list, # The map or adjacency list to be checked.
    space, # Specifies the space of valid references.
    template, # Specifies a filter over this space (or nothing).
    name, # Name the list being checked, useful for error messages.
    item; # Name the values referenced to, useful for error messages.
    allow_missing = true, # Lower to check that all possible references are given.
)

    # Exclude a few corner cases.
    (list isa UBinList && !allow_missing) &&
        argerr("Does disallowing missing values for binary lists make sense?")

    if list isa UList{Symbol}
        isnothing(space) && argerr("No index provided for checking label references.")
        (space isa Index || space isa Tuple{Index,Index}) ||
            argerr("Reference space is invalid to check label references: $(repr(space)).")
    end

    # Infer numerical space from indexes if required.
    if list isa UList{Int64}
        if !isnothing(space)
            space isa Index && (space = length(space))
            space isa Tuple{Index,Index} && (space = length.(space))
            (space isa Int || space isa Tuple{Int64} || space isa Tuple{Int64,Int64}) ||
                argerr("Reference space is invalid \
                        to check indices references: $(repr(space)).")
        end
        if !(isnothing(template) || isnothing(space))
            a, b = size(template), space
            (a == b || a == (b,) || a == (b, b)) ||
                argerr("Inconsistent template size vs. references space: $a vs. $b.")
        end
    end

    # If edges space for source and target are the same, allow elision.
    if list isa UAdjacency
        (space isa Int64 || space isa Index) && (space = (space, space))
    end

    # Possibly infer the (integer) space from a template if none is given.
    if isnothing(space)
        isnothing(template) &&
            argerr("Cannot infer reference space if no template is given.")
        space = size(template)
        length(space) == 1 && ((space,) = space)
    end

    # Check that there is anything to check.
    if empty_space(space) && !isempty(list)
        lv = level(list)
        rt = reftype(list)
        checkfails("No possible valid $lv $rt in '$name' \
                   like $(disp_access(first(accesses(list)))): \
                   the reference space for '$item' is empty.")
    end

    # Check references against their space.
    for acc in accesses(list)
        inspace(acc, space) && continue
        lv = level(list)
        rt = reftype(list)
        checkfails("Invalid '$item' $lv $rt in '$name'. \
                    $(outspace(acc, space, get_value(list, acc)))")
    end

    # Check against their template if any.
    isnothing(template) || check_templated_refs(list, space, template, name, item)

    # Check for density if required.
    allow_missing || check_missing_refs(list, space, template, name, item)

    true # For use within @test macro.
end

# For error messages.
level(::UMap) = "node"
level(::UAdjacency) = "edge"
reftype(::UList{Int64}) = "index"
reftype(::UList{Symbol}) = "label"
reftypes(::UList{Int64}) = "indices"
reftypes(::UList{Symbol}) = "labels"
outspace(acc, n::Int64, val) =
    "Index does not fall within the valid range 1:$n: $(disp_access(acc)) ($(repr(val)))."
outspace(acc, x::Index, val) =
    "Expected $(either(keys(x))), got instead: $(disp_access(acc)) ($(repr(val)))."
function outspace((i, j), (n, m), val)
    ref, space = inspace((i,), n) ? (j, m) : (i, n)
    outspace((ref,), space, val)
end
either(symbols) =
    length(symbols) == 1 ? "$(repr(first(symbols)))" :
    "either " * join_elided(sort(collect(symbols)), ", ", " or "; max = 12)

#-------------------------------------------------------------------------------------------
# Assuming the above check passed, check references against a template.

# Cast any access to an integer given its space.
to_index((i,), ::Int64) = i
to_index((s,), x::Index) = x[s]
to_index((a, b), (x, y)) = (to_index((a,), x), to_index((b,), y))

# Extract an index reference checker from a template.
function index_checker(template::AbstractSparseVector)
    nz = Set(findnz(template)[1])
    ref -> ref in nz
end
function index_checker(template::AbstractSparseMatrix)
    nz = Set(zip(findnz(template)[1:2]...))
    ref -> ref in nz
end

function check_templated_refs(list, space, template, name, item)
    complies_to_template = index_checker(template)
    for acc in accesses(list)
        index = to_index(acc, space)
        complies_to_template(index) && continue
        lv = level(list)
        rt = reftype(list)
        val = get_value(list, acc)
        checkfails("Invalid '$item' $lv $rt in '$name': \
                    $(disp_access(acc)) ($(repr(val))). \
                    $(valids(index, acc, space, template, reftypes(list)))")
    end
end

# For error messages.
valids(template::SparseVector) = findnz(template)[1]
valids(::Int64, template::SparseVector) = valids(template)
function valids(x::Index, template::SparseVector)
    revmap = Dict(i => n for (n, i) in x)
    [revmap[i] for i in valids(template)]
end
function valids(_, __, space, template::SparseVector, rts)
    vals = valids(space, template)
    "Valid nodes $rts for this template are:\n  $vals"
end
function valids((i, j), (a, b), (x, y), template::SparseMatrix, rts)
    vals = valids(y, template[i, :])
    src = disp_access((a,))
    if isempty(vals)
        "This template allows no valid edge targets $rts for source $src."
    else
        "Valid edges target $rts for source $src in this template are:\n  $vals"
    end
end

#-------------------------------------------------------------------------------------------
# Checking missing refs, either against a template or against the whole space if none.

# (ASSUMING all refs are valid)
miss_refs(map::UMap, n::Int64, ::Nothing) = length(map) < n
miss_refs(map::UMap, x::Index, ::Nothing) = length(map) < length(x)
function miss_refs(map::UMap, _, template::AbstractSparseVector)
    nz, _ = findnz(template)
    length(map) < length(nz)
end

function miss_refs(adj::UAdjacency, (m, n)::Tuple{Int64,Int64}, ::Nothing)
    length(adj) < m && return true
    for (_, sub) in adj
        length(sub) < n && return true
    end
    false
end
function miss_refs(adj::UAdjacency, (x, y)::Tuple{Index,Index}, ::Nothing)
    (m, n) = length.((x, y))
    miss_refs(adj, (m, n), nothing)
end
function miss_refs(adj::UAdjacency, _, template::AbstractSparseMatrix)
    nz, _ = findnz(template)
    sum(length(sub) for (_, sub) in adj) < length(nz)
end

needles(n::Int64, ::Nothing) = ((i,) for i in 1:n)
needles(x::Index, ::Nothing) = ((k,) for k in keys(x))
needles((m, n)::Tuple{Int64,Int64}, ::Nothing) = ((i, j) for i in 1:m, j in 1:n)
needles((x, y)::Tuple{Index,Index}, ::Nothing) = ((p, q) for p in keys(x), q in keys(y))
needles(::Int64, template::AbstractSparseVector) = ((i,) for i in findnz(template)[1])
needles(::Tuple{Int64,Int64}, template::AbstractSparseMatrix) =
    (access for access in zip(findnz(template)[1:2]...))
function needles(x::Index, template::AbstractSparseVector)
    revmap = Dict(i => n for (n, i) in x)
    sort!(collect((revmap[i],) for i in findnz(template)[1]))
end
function needles((x, y)::Tuple{Index,Index}, template::AbstractSparseMatrix)
    xrev = Dict(i => m for (m, i) in x)
    yrev = Dict(j => n for (n, j) in y)
    res = collect((xrev[i], yrev[j]) for (i, j) in zip(findnz(template)[1:2]...))
    sort!(res)
end

check_missing_refs(list, space, template, name, item) =
    if miss_refs(list, space, template)
        # Dummy linear searches to include one missing ref in error messages.
        # Assume there must be one because `miss_refs` returned true.
        haystack = Set(accesses(list))
        for needle in needles(space, template)
            needle in haystack && continue
            lv = level(list)
            rt = reftype(list)
            checkfails("Missing '$item' $lv $rt in '$name': \
                        no value specified for $(disp_access(needle)).")
        end
    end

#-------------------------------------------------------------------------------------------
# Convenience macros.

# Syntax:
#   @check_list_refs <list> <item> [<space>] [template(<..>)] [dense]
# (three last inputs optional)
macro check_list_refs(name::Symbol, item, input...)
    space, template, dense = parse_check_list_refs_input(input)
    list, space, template = esc.((name, space, template))
    varsymbol = Meta.quot(name)
    quote
        check_list_refs(
            $list,
            $space,
            $template,
            $varsymbol,
            $item;
            allow_missing = $(!dense),
        )
    end
end
export @check_list_refs

function parse_check_list_refs_input(input)
    kw = Dict{Symbol,Any}()
    for i in input
        if i == :dense
            haskey(kw, :dense) && argerr("Keyword 'dense' specified twice.")
            kw[:dense] = true
            continue
        end
        (false) && (local tp) # (reassure JuliaLS)
        @capture(i, template(tp_))
        if !isnothing(tp)
            haskey(kw, :template) &&
                argerr("Two 'template' specified: $(repr(kw[:template])) and $(repr(tp))")
            kw[:template] = tp
            continue
        end
        haskey(kw, :space) &&
            argerr("Two 'space' specified: $(repr(kw[:space])) and $(repr(i))")
        kw[:space] = i
    end
    miss = s -> !haskey(kw, s)
    take_or! = (s, d) -> miss(s) ? d : pop!(kw, s)
    (miss(:space) && miss(:template)) &&
        argerr("Specify at least a 'space' or a 'template'.")
    (take_or!(:space, nothing), take_or!(:template, nothing), take_or!(:dense, false))
end

# ==========================================================================================
# Ease use.

# Sugar for these awkward patterns:
#   var isa Symbol && @check_symbol(var, ...)
macro check_if_symbol(var::Symbol, list)
    @defloc
    check = _check_symbol(loc, var, list)
    var = esc(var)
    quote
        $var isa Symbol && $check
    end
end
export @check_if_symbol

# Sugar for these awkward patterns:
#   var isa Vector && @check_size(var, ...)
#   var isa Matrix && @check_size(var, ...)
macro check_size_if_vector(var::Symbol, size)
    check = _check_size(var, size)
    var = esc(var)
    quote
        $var isa AbstractVector && $check
    end
end
export @check_size_if_vector
macro check_size_if_matrix(var::Symbol, size)
    check = _check_size(var, size)
    var = esc(var)
    quote
        $var isa AbstractMatrix && $check
    end
end
export @check_size_if_matrix

# Sugar for these awkward patterns:
#   var isa AbstractSparseVector && @check_template(var, ...)
#   var isa AbstractSparseMatrix && @check_template(var, ...)
# WARN: This abstracts over Vector/Matrix
# because I can think of no reason we would accept
# either sparse vector OR sparse matrix input for now.
# Reconsider if needed.
macro check_template_if_sparse(var::Symbol, template, item)
    @defloc
    varsymbol = Meta.quot(var)
    var, template = esc.((var, template))
    quote
        $var isa AbstractSparseArray && check_template($varsymbol, $var, $template, $item)
    end
end
export @check_template_if_sparse

#   var isa <..> && @check_list_refs(var, ...)
macro check_refs_if_list(name::Symbol, item, input...)
    space, template, dense = parse_check_list_refs_input(input)
    list, space, template = esc.((name, space, template))
    varsymbol = Meta.quot(name)
    quote
        $list isa UList && check_list_refs(
            $list,
            $space,
            $template,
            $varsymbol,
            $item;
            allow_missing = $(!dense),
        )
    end
end
export @check_refs_if_list

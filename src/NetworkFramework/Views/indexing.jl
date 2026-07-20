# Factorize here checked indexing logic among all views.
# XXX: test indexing into views with `::Colon` e.g. `views[:a, :]`.

const Ref = Union{Int,Symbol} # Reference a node eitheir by index or label.
const Query = Union{Ref,UnitRange,CartesianIndex,Colon} # Anything accepted as view[q...].

# ==========================================================================================
# Checking access, with useful reporting on invalid queries.

#-------------------------------------------------------------------------------------------
# Check number of indexing dimensions.

function check_dim(v::AbstractView, q...)
    d = dispatcher(v)
    l = titlecase(D.level(d))
    exp = D.dim(d)
    act = length(q)
    s = exp == 1 ? "" : "s"
    err(v, "$l-level data has $exp dimension$s, received $act:")
end

check_dim(::NodesView, i) = (i,)
check_dim(::EdgesView, i, j) = (i, j)

#-------------------------------------------------------------------------------------------
# Check query type, per dimension.

check_type(v::AbstractView, q::Tuple) = check_type.((v,), q)
check_type(::AbstractView, q::Query) = q
check_type(v::AbstractView, q) =
    err(v, "Views are queried with indices [::Int] or labels [::Symbol], not $(typeof(q)):")

# Allow for a few implicit conversions.
check_type(::AbstractView, q::Union{Char,AbstractString}) = Symbol(q)
check_type(v::AbstractView, q::Unsigned) =
    try
        Int(q)
    catch e
        e isa InexactError && err(v, "Index too large: $q.", rethrow)
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Check intrinsic query value.

function check_value(v::AbstractView, i::Int, c)
    i > 0 && return i
    err(v, "Nodes can only be indexed with positive integers.")
end

check_value(::AbstractView, q, _) = q # Nothing to check otherwise.
check_value(v::NodesView, (i,)) = (check_value(v, i, Val(N.class)),)
check_value(v::EdgesView, (i, j)) = check_value.(v, (i, j), Val.((N.source, N.target)))

#-------------------------------------------------------------------------------------------
# Check query against the model.

check_query(v::NodesView, (i,)) = (check_query(v, i, Val(N.class)),) # TODO: subnodes differ.

function check_query(v::EdgesView, (i, j))
    check_query((v,), (i, j), Val.((N.source, N.target)))
    check_edge(v, (i, j)) # TODO
end

function check_query(v::AbstractView, r::Ref, c::Val{class}) where {class}
    check_value(v, r, c)
    N.is_ref(class(v).index, r) && return r
    referr(v, r)
end

referr(v::AbstractView, l::Symbol) = err(v, "No node in this class is labeled $(repr(l)).")
function referr(v::AbstractView, ::Int)
    n = length(N.class(v))
    s = n == 1 ? "" : "s"
    err(v, "This class only contains $n node$s.")
end

# ==========================================================================================
# Assuming all checks passed, finally obtain the indexed value.

function obtain(v::NodesFieldView, (r,)::Tuple{Ref})
    i = N.to_index(N.class(v).index, r)
    read(N.entry(v)) do data
        data[i]
    end
end

obtain(v::NodesNamesView, (r,)::Tuple{Ref}) = N.to_label(N.class(v).index, r)

# ==========================================================================================

# The exposed interface.
function Base.getindex(v::AbstractView, q...)
    this() = "$(dispatcher(v)) $(type_info(typeof(v)))"
    that() = display_query(q)
    # Report input context at the end of the message before it's dim/size checked
    # because there are stronger chances that it be very long.
    ctx_after(err) = "$err\nCannot index into $(this()) with $(that())."
    # Once checked, readability is likely better with the received query on top.
    ctx_before(err) = "Cannot index with $(that()) into $(this()):\n$err"
    # Checking sequence.
    q = fwd_err(ctx_after, check_dim, v, q...)
    q = fwd_err(ctx_after, check_type, v, q)
    q = fwd_err(ctx_before, check_value, v, q)
    q = fwd_err(ctx_before, check_query, v, q)
    obtain(v, q)
end
display_query(q) = "[" * join_elided(q, ", ") * "]"

# Factorize here checked indexing logic among all views.
# XXX: test indexing into views with `::Colon` e.g. `views[:a, :]`.
# HERE: keep importing all logic from the old indexing file on hold.

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
    qerr(v, q, false, "$l-level data has $exp dimension$s, received $act")
end

check_dim(::NodesView, i) = (i,)
check_dim(::EdgesView, i, j) = (i, j)

#-------------------------------------------------------------------------------------------
# Check query type.

# Then dispatch to per-dimension checking.
check_type(v::AbstractView, q::Tuple) = check_type.((v,), q)
check_type(::AbstractView, q::Query) = q
check_type(::AbstractView, q) =
    referr("Views are queried with indices [::Int] or labels [::Symbol]")

# Allow for a few implicit conversions.
check_type(::AbstractView, q::Union{Char,AbstractString}) = Symbol(q)
check_type(::AbstractView, q::Unsigned) =
    try
        Int(q)
    catch e
        e isa InexactError &&
            referr("Index too large to be used with julia arrays ($q)", rethrow)
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Check intrinsic query value, per dimension.

# Then dispatch to per-dimension checking.
check_value(::AbstractView, q, _) = q
check_value(v::NodesView, (i,)) = (check_value(v, i, Val(N.class)),)
check_value(v::EdgesView, (i, j)) = check_value.(v, (i, j), Val.((N.source, N.target)))

function check_value(::AbstractView, i::Int, c)
    i > 0 && return i
    referr("Integer node references can only be positive")
end

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

referr(::AbstractView, l::Symbol) = referr("No node in this class is labeled $(repr(l))")
function referr(v::AbstractView, ::Int)
    n = length(N.class(v))
    s = n == 1 ? "" : "s"
    referr("This class only contains $n node$s")
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

# The exposed interface: whole checking sequence.
function Base.getindex(v::AbstractView, q...)
    q = check_dim(v, q...)
    q = guard(false, check_type, v, q)
    q = guard(true, check_value, v, q)
    q = guard(true, check_query, v, q)
    obtain(v, q)
end

# Guard with error upgrade.
guard(typechecked, fn, v, q) =
    try
        fn(v, q)
    catch e
        e isa RefErr && qerr(v, q, typechecked, e.mess, rethrow)
        rethrow(e)
    end

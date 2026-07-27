# Factorize here checked indexing logic among all views.
# HERE: keep importing all logic from the old indexing file on hold.

# Anything accepted as view[q...].
const Ref = Union{Int,Symbol} # Reference a node eitheir by index or label.
const NodeMask = AbstractVector{Bool} # Boolean query.
const EdgeMask = AbstractMatrix{Bool}
const Query = Union{Ref,UnitRange,CartesianIndex,Colon,NodeMask,EdgeMask}

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

check_type(::AbstractView, q::AbstractArray{<:Integer}) =
    try
        copyto!(similar(q, Bool), q)
    catch e
        e isa InexactError &&
            referr("Could not interpret as a boolean mask (not only 1's and 0's?)", rethrow)
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

# Indexing with ranges.
function check_query(v::AbstractView, u::UnitRange, c)
    f, l = check_query.((v,), (first(u), last(u)), (c,))
    f:l
end

# Indexing with colon, meaning 'all'. Always valid.
check_query(::AbstractView, ::Colon, _) = (:)

# Indexing with masks.
function check_query(v::NodesView, m::NodeMask, ::Val{class}) where {class}
    exp = v |> class |> length
    act = length(m)
    exp == act && return m
    are, s = exp == 1 ? ("is", "") : ("are", "s")
    referr("The given mask is of size $act but there $are $exp node$s in the class")
end

# ==========================================================================================
# Assuming all checks passed, finally obtain the indexed value.

obtain(v::NodesView, (q,)::Tuple{Query}) = obtain(v, q)

function obtain(v::NodesFieldView, q::Query)
    i = N.to_index(N.class(v).index, q)
    read(N.entry(v)) do data
        data[i]
    end
end

# Node names.
obtain(v::NodesNamesView, r::Ref) = N.to_label(N.class(v).index, r)
obtain(v::NodesNamesView, u::UnitRange) = [obtain(v, i) for i in u]
obtain(v::NodesNamesView, ::Colon) = [obtain(v, i) for i in 1:length(v)]
obtain(v::NodesNamesView, m::NodeMask) = [obtain(v, i) for i in 1:length(v) if m[i]]

# ==========================================================================================

# The exposed interface: whole checking sequence.
function Base.getindex(v::AbstractView, q...)
    println("raw: $(repr(q)) ::$(typeof(q))")

    q = check_dim(v, q...)
    println("dim: $(repr(q)) ::$(typeof(q))")

    q = guard(false, check_type, v, q)
    println("type: $(repr(q)) ::$(typeof(q))")

    q = guard(true, check_value, v, q)
    println("value: $(repr(q)) ::$(typeof(q))")

    q = guard(true, check_query, v, q)
    println("query: $(repr(q)) ::$(typeof(q))")

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

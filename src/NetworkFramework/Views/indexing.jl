# Factorize here checked indexing logic among all views.
# HERE: keep importing all logic from the old indexing file on hold.

# Anything accepted as view[q...].
const Ref = Union{Int,Symbol} # Reference a node eitheir by index or label.

# ==========================================================================================
# Checking access, with useful reporting on invalid queries.

#-------------------------------------------------------------------------------------------
# Check number of indexing dimensions.

check_dim(::NodeView, i) = (i,)
check_dim(::EdgeView, i, j) = (i, j)
check_dim(v::AbstractView, q...) = dimerr(v, q, false, length(q))

check_dim(::NodeView, c::CartesianIndex{1}) = c
check_dim(::EdgeView, c::CartesianIndex{2}) = c
check_dim(v::AbstractView, c::CartesianIndex{N}) where N = dimerr(v, c, true, N)

function dimerr(v, q, sh, act)
    d = dispatcher(v)
    l = titlecase(D.level(d))
    exp = D.dim(d)
    s = exp == 1 ? "" : "s"
    qerr(v, q, sh, "$l-level data has $exp dimension$s, received $act")
end

check_dim(v::NodeView, q::Tuple) = tuplerr(v, q)
check_dim(v::EdgeView, q::Tuple) = tuplerr(v, q)
tuplerr(v, q) = qerr(v, q, false, "Cannot index into views with explicit tuples")

#-------------------------------------------------------------------------------------------
# Check query type.

# Then dispatch to per-dimension checking.
check_type(v::AbstractView, q::Tuple) = check_type.((v,), q)
check_type(::AbstractView, q::Union{Ref,UnitRange,CartesianIndex,Colon}) = q
check_type(::AbstractView, q) =
    referr("Views are queried with indices [::Int] or labels [::Symbol]")

# Allow for a few implicit conversions.
check_type(::AbstractView, q::Union{Char,AbstractString}) = Symbol(q)
check_type(::AbstractView, q::Unsigned) =
    try
        Int(q)
    catch e
        e isa InexactError || rethrow(e)
        referr("Index too large to be used with julia arrays ($q)", rethrow)
    end

check_type(::AbstractView, q::AbstractArray{<:Integer}) =
    try
        to_mask(q)
    catch e
        e isa InexactError || rethrow(e)
        referr("Could not interpret as a boolean mask (not only 1's and 0's?)", rethrow)
    end

function to_mask(q::Union{AbstractArray,BitArray})
    res = spzeros(Bool, size(q))
    for (i, r) in enumerate(q)
        res[i] = Bool(r)
    end
    res
end

function to_mask(q::AbstractSparseArray)
    res = spzeros(Bool, size(q))
    for (i, j, r) in zip(findnz(q)...)
        res[i, j] = Bool(r)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Check intrinsic query value, per dimension.

check_value(::AbstractView, q, _) = q

# Then dispatch to per-dimension checking.
check_value(v::NodeView, (i,)::Tuple) = (check_value(v, i, Val(N.class)),)
check_value(v::EdgeView, (i, j)::Tuple) =
    check_value.((v,), (i, j), Val.((N.source, N.target)))

function check_value(::AbstractView, i::Int, _)
    i > 0 && return i
    referr("Integer node references can only be positive")
end

# Cartesian is checked like the underlying tuple.
function check_value(v::AbstractView, c::CartesianIndex)
    check_value(v, Tuple(c))
    c
end

# Index 2D edge data with a mask.
function check_value(v::EdgeMaskView, (m,)::Tuple{SparseMatrix{Bool}})
    e, a = size.((v, m))
    e == a && return m
    referr("There are $e potential edges but the given mask is of size $a.")
end

#-------------------------------------------------------------------------------------------
# Check query against the model.

check_query(v::NodeView, (i,)::Tuple) = (check_query(v, i, Val(N.class)),) # TODO: subnodes differ.

function check_query(v::EdgeView, (i, j)::Tuple)
    check_query.((v,), (i, j), Val.((N.source, N.target)))
    check_edge(v, (i, j)) # TODO
end

function check_query(v::AbstractView, r::Ref, c::Val{class}) where class
    check_value(v, r, c)
    N.is_ref(class(v).index, r) && return r
    referr(v, r, Val(class))
end

referr(::NodeView, l::Symbol, ::Val{N.class}) =
    referr("No node in this class is labeled $(repr(l))")
function referr(v::NodeView, ::Int, ::Val{N.class})
    n = length(N.class(v))
    s = n == 1 ? "" : "s"
    referr("This class only contains $n node$s")
end

referr(v::EdgeView, l::Symbol, ::Val{class}) where class =
    referr("No node in the $class class ($(repr(class(v).name))) is labeled $(repr(l))")
function referr(v::EdgeView, ::Int, ::Val{class}) where class
    c = class(v)
    name = repr(c.name)
    n = length(c)
    s = n == 1 ? "" : "s"
    referr("The $class class ($name) only contains $n node$s")
end

# Indexing with ranges.
function check_query(v::AbstractView, u::UnitRange, c)
    f, l = check_query.((v,), (first(u), last(u)), (c,))
    f:l
end

# Indexing with colon, meaning 'all'. Always valid.
check_query(::AbstractView, ::Colon, _) = (:)

# Indexing with masks.
function check_query(v::NodeView, m::SparseVector{Bool}, ::Val{class}) where {class}
    exp = v |> class |> length
    act = length(m)
    exp == act && return m
    are, s = exp == 1 ? ("is", "") : ("are", "s")
    referr("The given mask is of size $act but there $are $exp node$s in the class")
end

# Cartesian is checked like the underlying tuple.
function check_query(v::AbstractView, c::CartesianIndex)
    check_value(v, Tuple(c))
    c
end

# Edges.
check_edge(::EdgeMaskView, q) = q # Ok if marginal indices are ok.
function check_edge(v::EdgeFieldView, (i, j)::Tuple{Ref,Ref})
    is_edge(v, (i, j)) || referr("Not an edge")
    (i, j)
end

function is_edge(v::EdgeView, (i, j)::Tuple{Ref,Ref})
    w = N.web(v)
    s, t = N.source(v), N.target(v)
    t, x, y = w.topology, s.index, t.index
    i, j = N.to_index.((x, y), (i, j))
    N.is_edge(t, i, j)
end

check_query(::EdgeMaskView, m::SparseMatrix{Bool}) = m # As long as dimensions are ok.

# ==========================================================================================
# Assuming all checks passed, finally obtain the indexed value(s).

obtain(v::NodeView, (q,)::Tuple{Any}) = obtain(v, q)

function obtain(v::NodeFieldView, q)
    i = N.to_index(N.class(v).index, q)
    read(N.entry(v)) do data
        data[i]
    end
end

# Node names and mask.
obtain(v::NodeNameView, r::Ref) = N.to_label(N.class(v).index, r)
obtain(v::NodeMaskView, r::Ref) = N.is_ref(N.class(v).index, r)

obtain(v::NodeTopologyView, u::UnitRange) = [obtain(v, i) for i in u]
obtain(v::NodeTopologyView, ::Colon) = [obtain(v, i) for i in 1:length(v)]
obtain(v::NodeTopologyView, m::SparseVector{Bool}) =
    [obtain(v, i) for i in 1:length(v) if m[i]]

# Edges masks.
obtain(v::EdgeMaskView, q::Tuple) = is_edge(v, q)

# Redirect cartesian index like the underlying tuple.
obtain(v::AbstractView, c::CartesianIndex) = obtain(v, Tuple(c))

# Accept mixtures of ranges and scalars.
function obtain(v::EdgeMaskView, (i, rj)::Tuple{Ref,UnitRange})
    res = spzeros(Bool, length(rj))
    for j in rj
        k = j - first(rj) + 1
        res[k] = obtain(v, (i, j))
    end
    res
end
function obtain(v::EdgeMaskView, (ri, j)::Tuple{UnitRange,Ref})
    res = spzeros(Bool, length(ri))
    for i in ri
        k = i - first(ri) + 1
        res[k] = obtain(v, (i, j))
    end
    res
end
function obtain(v::EdgeMaskView, (ri, rj)::Tuple{UnitRange,UnitRange})
    res = spzeros(Bool, (length(ri), length(rj)))
    for i in ri, j in rj
        ki = i - first(ri) + 1
        kj = j - first(rj) + 1
        res[ki, kj] = obtain(v, (i, j))
    end
    res
end

# 2D indexing into edges mask.
function obtain(v::EdgeMaskView, m::SparseMatrix{Bool})
    is, js, _ = findnz(m)
    res = spzeros(Bool, length(is))
    for (r, (i, j)) in enumerate(zip(is, js))
        res[r] = obtain(v, (i, j))
    end
    res
end

# ==========================================================================================
# Assuming all checks passed, finally edit the indexed value(s).

set!(::FieldView, q, rhs) = throw("TODO")

# ==========================================================================================
# Exposed interface: whole checking sequence.

function check_all(v::AbstractView, q)
    q = check_dim(v, q...)
    q = guard(false, check_type, v, q)
    q = guard(true, check_value, v, q)
    q = guard(true, check_query, v, q)
    q
end

# 2D-mask boolean indexing breaks the above flow: 1 argument for 2 dimensions.
function check_all(v::EdgeMaskView, (q,)::Tuple{Any})
    can_convert(SparseMatrix{Bool}, q) || # (hopefully resolved statically)
        return @invoke check_all(v::AbstractView, (q,))
    q = guard(false, check_type, v, (q,))
    q = guard(false, check_value, v, q)
    q = guard(false, check_query, v, q)
    q
end

# Guard with error upgrade.
guard(short, fn, v, q) =
    try
        fn(v, q)
    catch e
        e isa RefErr && qerr(v, q, short, e.mess, rethrow)
        rethrow(e)
    end

# Into julia endpoint.
function Base.getindex(v::AbstractView, q...)
    q = check_all(v, q)
    obtain(v, q)
end

Base.setindex!(v::Union{TopologyView,EdgeMaskView}, _...) = throw(ImmutableError(v))
function Base.setindex!(v::FieldView, rhs, q...)
    q = check_all(v, q)
    set!(v, q, rhs)
end

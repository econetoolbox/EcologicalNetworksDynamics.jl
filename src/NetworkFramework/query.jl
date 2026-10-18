"Checked transformation of a query into a reference into model data"
module Query

using EcologicalNetworksDynamics.NetworkFramework:
    D, N, NF, Dispatcher, dispatcher, CheckError, checkerr, SparseMatrix, SparseVector,
    Ref, _WholeData, Model
using EcologicalNetworksDynamics.Display: join_elided, render_input, ns

using SparseArrays

# ==========================================================================================
# Check number of indexing dimensions.

dim_check(::D.NodeLevel, i) = (i,)
dim_check(::D.EdgeLevel, i, j) = (i, j)
dim_check(d::Dispatcher, q...) = dimerr(d, q, false, length(q))

dim_check(::D.NodeLevel, c::CartesianIndex{1}) = c
dim_check(::D.EdgeLevel, c::CartesianIndex{2}) = c
dim_check(d::Dispatcher, c::CartesianIndex{N}) where N = dimerr(d, c, true, N)

function dimerr(d, q, sh, act)
    d = dispatcher(d)
    l = titlecase(D.level(d))
    exp = D.dim(d)
    s = exp == 1 ? "" : "s"
    checkerr(q, sh, "$l-level data has $exp dimension$s, received $act"; d)
end

dim_check(d::D.NodeLevel, q::Tuple) = tuplerr(d, q)
dim_check(d::D.EdgeLevel, q::Tuple) = tuplerr(d, q)
tuplerr(d, q) = checkerr(q, false, "Cannot index into views with explicit tuples"; d)

# ==========================================================================================
# Check query type.

# Then dispatch to per-dimension checking.
type_check(d::Dispatcher, q::Tuple) = type_check.((d,), q)
type_check(::Dispatcher, q::Union{Ref,UnitRange,CartesianIndex,Colon}) = q
type_check(d::Dispatcher, q) =
    checkerr(q, "Views are queried with indices [::Int] or labels [::Symbol]"; d)

# Allow for a few implicit conversions.
type_check(::Dispatcher, q::Union{Char,AbstractString}) = Symbol(q)
type_check(d::Dispatcher, q::Unsigned) =
    try
        Int(q)
    catch e
        e isa InexactError || rethrow(e)
        checkerr(q, "Index too large to be used with julia arrays ($q)", rethrow; d)
    end

type_check(d::Dispatcher, q::AbstractArray{<:Integer}) =
    try
        to_mask(q)
    catch e
        e isa InexactError || rethrow(e)
        checkerr(q,
            "Could not interpret as a boolean mask (not only 1's and 0's?)",
            rethrow; d)
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

# ==========================================================================================
# Check intrinsic query value, per dimension.

early_check(::Dispatcher, q, _) = q

# Then dispatch to per-dimension checking.
early_check(d::D.NodeLevel, (i,)::Tuple) = (early_check(d, i, Val(N.class)),)
early_check(d::D.EdgeLevel, (i, j)::Tuple) =
    early_check.((d,), (i, j), Val.((N.source, N.target)))

function early_check(d::Dispatcher, i::Int, _)
    i > 0 && return i
    checkerr(i, "Integer node references can only be positive"; d)
end

# Cartesian is checked like the underlying tuple.
function early_check(d::Dispatcher, c::CartesianIndex)
    early_check(d, Tuple(c))
    c
end

# Index 2D edge data with a mask.
function early_check(d::D.Web, (m,)::Tuple{SparseMatrix{Bool}})
    e, a = size.((d, m))
    e == a && return m
    checkerr(m, "There are $e potential edges but the given mask is of size $a."; d)
end

# ==========================================================================================
# Check query against the model.

late_check(d::D.NodeLevel, md::Model, (i,)::Tuple) = (late_check(d, md, i, Val(N.class)),)
late_check(d::D.Subclass, md::Model, (i,)::Tuple) = (late_check(d, md, i, Val(N.parent)),)

function late_check(d::D.EdgeLevel, md::Model, (i, j)::Tuple)
    late_check.((d,), (md,), (i, j), Val.((N.source, N.target)))
    check_edge(d, md, (i, j)) # TODO
end

function late_check(d::Dispatcher, md::Model, r::Ref, c::Val{class}) where class
    early_check(d, r, c)
    ix = class(d, md).index
    N.is_ref(ix, r) && return r
    referr(d, md, r, Val(class))
end

referr(d::D.NodeLevel, ::Model, l::Symbol, ::Val{N.class}) =
    checkerr(l, "No node in this class is labeled $(repr(l))"; d)
referr(d::D.Subclass, ::Model, l::Symbol, ::Val{N.parent}) =
    checkerr(l, "No node in the parent class is labeled $(repr(l))"; d)
referr(d::D.EdgeLevel, md::Model, l::Symbol, ::Val{class}) where class =
    checkerr(l,
        "No node in the $class class ($(repr(class(d, md).name))) is labeled $(repr(l))"; d)

function referr(d::D.NodeLevel, md::Model, i::Int, ::Val{N.class})
    n, s = ns(length(N.class(md, d)))
    checkerr(i, "This class only contains $n node$s"; d)
end

function referr(d::D.NodeLevel, md::Model, i::Int, ::Val{N.parent})
    n, s = ns(length(N.parent(md, d)))
    checkerr(i, "The parent class only contains $n node$s"; d)
end

function referr(d::D.EdgeLevel, md::Model, i::Int, ::Val{class}) where class
    c = class(d, md)
    name = repr(c.name)
    n, s = ns(length(c))
    checkerr(i, "The $class class ($name) only contains $n node$s"; d)
end

# Indexing with ranges.
function late_check(d::Dispatcher, md::Model, u::UnitRange, c)
    f, l = late_check.((d,), (md,), (first(u), last(u)), (c,))
    f:l
end

# Indexing with colon, meaning 'all'. Always valid.
late_check(::Dispatcher, ::Model, ::Colon, _) = (:)

# Indexing with masks.
function late_check(
    d::D.NodeLevel,
    md::Model,
    k::SparseVector{Bool},
    ::Val{class},
) where {class}
    exp = length(N.class(md, d))
    act = length(k)
    exp == act && return k
    are, s = exp == 1 ? ("is", "") : ("are", "s")
    checkerr(k, "The given mask is of size $act but there $are $exp node$s in the class"; d)
end

# Cartesian is checked like the underlying tuple.
function late_check(d::Dispatcher, ::Model, c::CartesianIndex)
    early_check(d, Tuple(c))
    c
end

# Edges.
check_edge(::D.Web, ::Model, q) = q # Ok if marginal indices are ok.
function check_edge(d::D.EdgeField, md::Model, (i, j)::Tuple{Ref,Ref})
    is_edge(d, md, (i, j)) || checkerr((i, j), "Not an edge"; d)
    (i, j)
end

function is_edge(d::D.EdgeLevel, md::Model, (i, j)::Tuple{Ref,Ref})
    web = N.web(md, d)
    src, tgt = N.source(web), N.target(web)
    t, x, y = web.topology, src.index, tgt.index
    i, j = N.to_index.((x, y), (i, j))
    N.is_edge(t, i, j)
end

late_check(::D.Web, ::Model, m::SparseMatrix{Bool}) = m # As long as dimensions are ok.

# ==========================================================================================
# Exposed interface: whole checking sequence.

check(d::Dispatcher, md::Model, q) =
    try
        q = dim_check(d, q...)
        q = type_check(d, q)
        q = early_check(d, q)
        q = late_check(d, md, q)
        q
    catch e
        e isa CheckError || rethrow(e)
        rethrow(Query.Error(q, d, e))
    end

# 2D-mask boolean indexing breaks the above flow: 1 argument for 2 dimensions.
function check(d::D.Web, md::Model, (q,)::Tuple{Any})
    NF.can_convert(SparseMatrix{Bool}, q) || # (hopefully resolved statically)
        return @invoke check(d::Dispatcher, md, (q,))
    try
        q = type_check(d, (q,))
        q = early_check(d, q)
        q = late_check(d, md, q)
        q
    catch e
        e isa CheckError || rethrow(e)
        rethrow(Query.Error(q, d, e))
    end
end

# Trivial, internal query analysis, invoked on 'reassign'.
check(::Dispatcher, ::Model, w::_WholeData) = w

# ==========================================================================================

"Contextualize failure within input meant to *query* data within the model."
mutable struct Error <: NF.LibError
    "The total, initial query *e.g.* typical arguments to julia indexing syntax `[...]`."
    query::Tuple
    "The queried data."
    d::Dispatcher
    "Underlying report."
    src::CheckError
end

function Base.showerror(io::IO, e::Error)
    (; d, query, src) = e
    report() = NF.render(io, src; what = "query", display_input = false)
    # Report either before or after depending on the query size.
    if length(repr(query)) <= 20
        # Easier to understand before..
        q = "[" * join_elided(query, ", ") * "]"
        println(io, "Cannot index with $q into $d:")
        report()
    else
        # .. unless the query would flood the report.
        report()
        if src.value != query
            println(io, "Cannot index into $d with: [")
            for q in query
                render_input(
                    io,
                    q,
                    (short, Q) -> "  $short ::$Q,\n",
                    (long, Q) -> begin
                        print(io, "  ")
                        long()
                        print(io, "  ::$Q,\n")
                    end,
                )
            end
        end
        print(io, "]")
    end
end

end

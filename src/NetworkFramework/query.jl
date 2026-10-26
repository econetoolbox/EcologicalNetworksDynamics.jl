"Checked transformation of a query into a reference into model data"
module Query

using EcologicalNetworksDynamics.NetworkFramework:
    I, D, N, NF, Dispatcher, dispatcher, CheckError, checkerr, SparseMatrix, SparseVector,
    Ref, WholeData, _WholeData, Model, LibError, nestref, urefguard
using EcologicalNetworksDynamics.Display: join_elided, render_input, ns, cyan, reset

using SparseArrays

# ==========================================================================================
# Check number of indexing dimensions.
# ONHOLD? rely on `AbstractArray`?

dim_check(::D.NodeLevel, i) = (i,)
dim_check(::D.EdgeLevel, i, j) = (i, j)
dim_check(d::Dispatcher, q...) = dimerr(d, q, length(q))

function dimerr(d, q, act)
    l = titlecase(D.level(d))
    exp = D.dim(d)
    s = exp == 1 ? "" : "s"
    checkerr(q, "$l-level data has $exp dimension$s, received $act."; d)
end

dim_check(d::D.NodeLevel, q::Tuple) = tuplerr(d, q)
dim_check(d::D.EdgeLevel, q::Tuple) = tuplerr(d, q)
tuplerr(d, q) = checkerr(q,
    "Cannot index into views with explicit tuples.";
    d, uref = nestref(1, WholeData))

# ==========================================================================================
# Check query type.

# Then dispatch to per-dimension checking.
type_check(d::Dispatcher, q::Tuple) = Tuple(urefguard(i) do
    type_check(d, q)
end for (i, q) in enumerate(q))

type_check(::Dispatcher, q::Ref) = q
type_check(d::Dispatcher, q) =
    checkerr(q, "Views are queried with indices [::Int] or labels [::Symbol], \
                 not `$(typeof(q))`."; d)

# Allow for a few implicit conversions.
type_check(::Dispatcher, q::Union{Char,AbstractString}) = Symbol(q)
type_check(d::Dispatcher, q::Unsigned) =
    try
        Int(q)
    catch e
        e isa InexactError || rethrow(e)
        checkerr(q, "Index too large to be used with julia arrays ($q).", rethrow; d)
    end

# ==========================================================================================
# Check intrinsic query value, per dimension.

early_check(::Dispatcher, q, _) = q

# Then dispatch to per-dimension checking.
early_check(d::D.NodeLevel, (i,)::Tuple) = urefguard(1) do
    (early_check(d, i, Val(N.class)),)
end
early_check(d::D.EdgeLevel, (i, j)::Tuple) = Tuple(
    urefguard(dim) do
        early_check(d, i, Val(class))
    end for (dim, (i, class)) in enumerate(zip((i, j), (N.source, N.target))))

function early_check(d::Dispatcher, i::Int, _)
    i > 0 && return i
    checkerr(i, "Integer node references can only be positive."; d)
end

early_check(::D.EdgeLevel, (m,)::Tuple{AbstractMatrix{Bool}}) = (m,)

# ==========================================================================================
# Check query against the model.

late_check(md::Model, d::D.NodeLevel, (i,)::Tuple{Any}) = urefguard(1) do
    (late_check(md, d, i, Val(N.class)),)
end
late_check(md::Model, d::D.Subclass, (i,)::Tuple{Any}) = urefguard(1) do
    (late_check(md, d, i, Val(N.parent)),)
end

late_check(md::Model, d::D.EdgeLevel, (i, j)::Tuple{Any,Any}) = Tuple(
    urefguard(dim) do
        late_check(md, d, i, Val(class))
        check_edge(md, d, i)
    end for (dim, (i, class)) in enumerate(zip((i, j), (N.source, N.target))))

function late_check(md::Model, d::Dispatcher, r::Ref, c::Val{class}) where class
    early_check(d, r, c)
    ix = class(md, d).index
    N.is_ref(ix, r) && return r
    referr(md, d, r, Val(class))
end

referr(::Model, d::D.NodeLevel, l::Symbol, ::Val{N.class}) =
    checkerr(l, "No node in this class is labeled $(repr(l))."; d)
referr(::Model, d::D.Subclass, l::Symbol, ::Val{N.parent}) =
    checkerr(l, "No node in the parent class is labeled $(repr(l))."; d)
referr(md::Model, d::D.EdgeLevel, l::Symbol, ::Val{class}) where class =
    checkerr(l,
        "No node in the $class class ($(repr(class(md, d).name))) is labeled $(repr(l)).";
        d)

function referr(md::Model, d::D.NodeLevel, i::Int, ::Val{N.class})
    n, s = ns(length(N.class(md, d)))
    checkerr(i, "This class only contains $n node$s."; d)
end

function referr(md::Model, d::D.NodeLevel, i::Int, ::Val{N.parent})
    n, s = ns(length(N.parent(md, d)))
    checkerr(i, "The parent class only contains $n node$s."; d)
end

function referr(md::Model, d::D.EdgeLevel, i::Int, ::Val{class}) where class
    c = class(md, d)
    name = repr(c.name)
    n, s = ns(length(c))
    checkerr(i, "The $class class ($name) only contains $n node$s."; d)
end

# Edges.
check_edge(::Model, ::D.Web, q) = q # Ok if marginal indices are ok.
function check_edge(md::Model, d::D.EdgeField, (i, j)::Tuple{Ref,Ref})
    is_edge(d, md, (i, j)) || checkerr((i, j), "Not an edge"; d)
    (i, j)
end

function is_edge(md::Model, d::D.EdgeLevel, (i, j)::Tuple{Ref,Ref})
    web = N.web(md, d)
    src, tgt = N.sides(md, d)
    t, x, y = web.topology, src.index, tgt.index
    i, j = N.to_index.((x, y), (i, j))
    N.is_edge(t, i, j)
end

# ==========================================================================================
# Exposed interface: the whole checking sequence.
# Statically allow-list the accepted query types
# so as to help `Views` rely on julia's implementations of `AbstractArray` interface *much*.
# This also reduces the surface to be supported within this module.

# Single-value access, using either indices or labels.
const Label = Union{Symbol,Char,AbstractString} # (matches our `convert`)
const Point = Union{Int,Label}
check(md::Model, d::D.NodeLevel, q::Tuple{Point}) = _check(md, d, q)
check(md::Model, d::D.EdgeLevel, q::Tuple{Point,Point}) = _check(md, d, q)

# Multiple-labels accesses, useful to match `view[[i, j, k]]` arrays of indices.
function check(md::Model, d::D.NodeLevel, (labels,)::Tuple{AbstractVector{<:Label}})
    ix = N.class(md, d).index
    res = sizehint!(Int[], length(labels))
    for (i, l) in pairs(I.map(Symbol, labels))
        N.is_ref(ix, l) || throw(
            Query.Error((labels,),
                CheckError(l, "No node in this class is labeled $(repr(l)).";
                    d, uref = (1, (i,)))))
        push!(res, N.to_index(ix, l))
    end
    (res,)
end

# .. although the implementation is the same regardless.
_check(md::Model, d::Dispatcher, q) =
    try
        q = dim_check(d, q...)
        q = type_check(d, q)
        q = early_check(d, q)
        q = late_check(md, d, q)
        q
    catch e
        e isa CheckError || rethrow(e)
        e.d = d
        rethrow(Query.Error(q, e))
    end

# Trivial, internal query analysis, invoked on 'reassign-like' mutation.
check(::Model, ::Dispatcher, w::_WholeData) = w

# ==========================================================================================

"Contextualize failure within input meant to *query* data within the model."
mutable struct Error <: NF.LibError
    "The total, initial query *e.g.* typical arguments to julia indexing syntax `[...]`."
    query::Tuple
    "Underlying report."
    src::CheckError
end

function Base.showerror(io::IO, e::Error)
    (; query, src) = e
    (; mess, value, d, uref, mref) = src
    function report() # Return true if value was displayed.
        openline = if uref === WholeData
            false
        else
            if irrelevant_uref(query, uref)
                false
            else
                # Uref is always expected to at least start with the index dimension here.
                dim, rest... = uref
                opendim = if !(query isa Tuple{Any})
                    print(io, "On dimension $dim")
                    true
                else
                    false
                end
                if !isempty(rest)
                    if opendim
                        print(io, ", in element ")
                    else
                        print(io, "In element ")
                    end
                    NF.print_uref(io, rest...)
                    print(io, " within the index")
                end
                true
            end
        end
        if NF.irrelevant_mref(mref, uref)
            if openline
                println(io, ":")
            end
        else
            mv = NF.modelvalue(d, mref)
            println(io, " referring to inner $mv:")
        end
        print(io, mess)
        if !irrelevant_uref(query, uref)
            println(io)
            render_input(io, value)
            true
        else
            false
        end
    end
    # Report either before or after depending on the query size.
    Cantwith = "Cannot index into $d with"
    if length(repr(query)) <= 20
        # Easier to understand before..
        q = "[" * join_elided(query, ", ") * "]"
        println(io, "$Cantwith $q:")
        report()
    else
        # .. unless the query would flood the report.
        if !report()
            println(io, "\n$Cantwith: [")
            for q in query
                render_input(
                    io,
                    q,
                    (short, Q) -> "  $cyan$short$reset  ::$Q,\n",
                    (long, Q) -> begin
                        print(io, "  $cyan")
                        long()
                        print(io, "$reset  ::$Q,\n")
                    end,
                )
            end
        end
        print(io, "]")
    end
end

"""
Raise if locating problematic input within the index is trivial,
resulting in the report being too noisy.
"""
irrelevant_uref(query, uref) =
    uref isa _WholeData || query isa Tuple{Any} && uref == (1,)

end

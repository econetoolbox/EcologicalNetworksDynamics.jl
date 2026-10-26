# Query-checking utils.

# Exposed dispatch points (smallest possible to delegate most to `AbstractArray`).
const Label = Union{Symbol,Char,AbstractString} # (matches our `convert`)
_query_check(vw::NodeView, q::Tuple{Int}) = query_check(vw, q)
_query_check(vw::NodeView, q::Tuple{Label}) = query_check(vw, q)
_query_check(vw::EdgeView, q::Tuple{Int,Int}) = query_check(vw, q)
_query_check(vw::EdgeView, q::Tuple{Label,Any}) = query_check(vw, q)
_query_check(vw::EdgeView, q::Tuple{Any,Label}) = query_check(vw, q)
_query_check(vw::EdgeView, q::Tuple{Label,Label}) = query_check(vw, q)

# Special-case arrays of labels.
_query_check(vw::NodeView, q::Tuple{AbstractVector{<:Label}}) = query_check(vw, q)

# Large underlying dispatch point (largest possible to avoid duplicating code).
query_check(vw::NodeView, q) = node_check(NF.model(vw), dispatcher(vw), q)
query_check(vw::EdgeView, q) = edge_check(NF.model(vw), dispatcher(vw), q)

# The sparse node mask view is indexed within its parent.
query_check(vw::NodeMaskView, q) =
    node_check(NF.model(vw), dispatcher(vw), q; class = N.parent)

# These ones, apparently specialized within julia, need disambiguation?
# TODO: that is fragile to internal julia changes,
# can we make better without having to support all the interface ourselves, or list it here?
for Q in (Integer, AbstractVector{Bool}, AbstractVector, UnitRange)
    eval(
        quote
            Base.getindex(vw::NodeMaskView, q::$Q) =
                invoke(getindex, Tuple{AbstractView,Any}, vw, q)
        end,
    )
end

# Single-value access, using either indices or labels.
function node_check(md::Model, d::D.NodeLevel, (i,)::Tuple{Int}; class = N.class)
    n = length(class(md, d))
    1 <= i <= n && return (i,)
    n, s, are = nsa(n)
    throw(V.Error((i,), CheckError(i, "There $are $n node$s in this class."; d)))
end

function node_check(md::Model, d::D.NodeLevel, (q,)::Tuple{Label}; class = N.class)
    l = Symbol(q)
    ix = class(md, d).index
    N.is_ref(ix, l) && return (N.to_index(ix, l),)
    throw(
        V.Error((l,), CheckError(l, "No node in this class is labeled $(repr(l))."; d)),
    )
end

# Large underlying dispatch point (largest possible to avoid duplicating code).
edge_check(md::Model, d::D.EdgeLevel, (a, b)::Tuple{Any,Any}) = (
    node_check(md, D.source(d)[1], (a,))...,
    node_check(md, D.target(d)[1], (b,))...,
)

# Multiple-labels accesses, useful to match `view[[i, j, k]]` arrays of indices.
function node_check(
    md::Model,
    d::D.NodeLevel,
    (labels,)::Tuple{AbstractVector{<:Label}};
    class = N.class,
)
    ix = class(md, d).index
    res = sizehint!(Int[], length(labels))
    for (i, raw) in pairs(labels)
        l = Symbol(raw)
        N.is_ref(ix, l) || throw(
            V.Error((labels,),
                CheckError(raw, "No node in this class is labeled $(repr(l)).";
                    d, uref = (1, (i,)))))
        push!(res, N.to_index(ix, l))
    end
    (res,)
end

# ==========================================================================================

"""
Contextualize failure within input meant to *query* data within the model.
TODO: this error type was designed to cover much more cases that it is covering now.
I think it may me much simplified.
"""
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
    Cantwith = "Cannot index into $cyan$d$reset with"
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


"Report invalid attempt to index with views."
struct QueryError <: NF.IndexError
    View::Type
    query::Tuple
    typechecked::Bool # Lower to make sure to display query at the end.
    mess::String
end
qerr(V::Type, q, t, m, throw = Base.throw) = throw(QueryError(V, q, t, m))
qerr(v, x...) = qerr(typeof(v), x...)

# Decide whether the error can assume that the query is short to display.
function short(e::QueryError)
    (; query, typechecked) = e
    length(query) == 0 && return true # Sure if it's empty.
    typechecked || return false # Not if input type is uncontrolled.
    query isa Tuple{AbstractArray} && return false # Uncertain if size is unbound.
    true # Otherwise okay.
end

function Base.showerror(io::IO, e::QueryError)
    (; View, query, mess) = e
    d = dispatcher(View)
    println(io, "View error ($(type_info(View))):")
    if short(e)
        # Can assume the query is short: insert anywhere.
        q = "[" * join_elided(query, ", ") * "]"
        println(io, "Cannot index with $q into $d:")
        println(io, mess, '.')
    else
        # The query has unbounded display: push it to the end.
        println(io, mess, ':')
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
        print(io, "]")
    end
end

"Raise to be later upgraded into a `QueryError`."
struct RefErr <: NF.LibError
    mess::String
end
referr(m, throw = Base.throw) = throw(RefErr(m))

"Report attempt to mutate through a view into immutable data."
struct ImmutableError <: NF.LibError
    View::Type
    ImmutableError(v::Type) = new(v)
end
ImmutableError(v) = ImmutableError(typeof(v))
function Base.showerror(io::IO, e::ImmutableError)
    (; View) = e
    d = dispatcher(View)
    print(io, "Cannot change $d $(type_info(View)) once they have been set.")
end

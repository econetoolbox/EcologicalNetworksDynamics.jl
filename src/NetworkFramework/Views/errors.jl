struct QueryError <: NF.LibError
    View::Type
    query::Tuple
    typechecked::Bool # Lower to make sure to display query at the end.
    mess::String
end
qerr(V::Type, q, t, m, throw = Base.throw) = throw(QueryError(V, q, t, m))
qerr(v, x...) = qerr(typeof(v), x...)
function Base.showerror(io::IO, e::QueryError)
    (; View, query, typechecked, mess) = e
    d = dispatcher(View)
    println(io, "View error ($(type_info(View))):")
    if typechecked || length(query) == 0
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

# Raised when checking only on dimension of the query.
# To be upgraded into a QueryError.
struct RefErr <: Exception
    mess::String
end
referr(m) = throw(RefErr(m))

# ONHOLD: can we not get the same with a clever use of the error type above?
struct WriteError <: Exception
    message::String
    fieldname::Symbol
    index::Any
    value::Any
end
function Base.showerror(io::IO, e::WriteError)
    (; fieldname, index, value, message) = e
    it, reset = crayon"italics", crayon"reset"
    print(
        io,
        "Cannot set node data $fieldname$(display_index(index)):\n\
         $it$message$reset\n\
         Received value: $(repr(value)) ::$(typeof(value))",
    )
end

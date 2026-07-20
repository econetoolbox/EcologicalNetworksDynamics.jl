struct Error <: Exception
    type::Type # (View type)
    mess::String
end
err(T::Type, m, throw = throw) = throw(Error(T, m))
err(t, x...) = err(typeof(t), x...)
Base.showerror(io::IO, e::Error) =
    print(io, "View error ($(type_info(e.type))):\n$(e.mess)")

# Forward error up after upgrading message with additional context.
fwd_err(upgrade, totry, a...) =
    try
        totry(a...)
    catch e
        e isa V.Error && err(e.type, upgrade(e.mess), rethrow)
        rethrow(e)
    end

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
display_index(i...) = display_index(i)
display_index(i::Tuple) = "[$(join(repr.(i), ", "))]"

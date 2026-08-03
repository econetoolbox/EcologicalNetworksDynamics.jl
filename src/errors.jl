import .Display: yellow, reset

"""
Use to throw or rethrow when the error is identified within user arguments.
"""
argerr(message, throw = Base.throw) = throw(ArgumentError(message))

"""
Use to create apparent one-shot error type,
passing just a closure capturing the environment required for display.
"""
struct ErrWith <: Exception
    headline::String
    display::Function
end
errwith(fn, head, throw = Base.throw) = throw(ErrWith(head, fn))
function Base.showerror(io::IO, e::ErrWith)
    (; headline, display) = e
    println(io, "$yellow$headline$reset")
    display(io)
end

"Same as above, but prefixing an underlying exception."
struct ErrWrap <: Exception
    with::ErrWith
    source
    stack::Base.ExceptionStack # Useful for testing stack frames at least.
end
"Rethrow by default, since this is expected to be called within `catch` blocks."
errwrap(fn::Function, src, head, throw = Base.rethrow) =
    throw(ErrWrap(ErrWith(head, fn), src, current_exceptions()))
errwrap(s, h, t = Base.rethrow) = errwrap(identity, s, h, t) # If header is enough context.
function Base.showerror(io::IO, e::ErrWrap)
    (; with, source) = e
    showerror(io, with)
    showerror(io, source)
end

"""
Construct this error type when 'asking forgiveness rather than permission' in a row,
and only consider failure if all attempts fail.
This error type will report all failed attempts with their stacktrace.
"""
struct FailedAttempts <: Exception
    errors::Vector # [(attempt description, exception, backtrace)]
    FailedAttempts() = new([])
end
Base.length(f::FailedAttempts) = length(f.errors)
Base.last(f::FailedAttempts) = last(f.errors)[2]

"""
Call within a `catch` block to append failure to the collection.
Provide context completing "attempting to:".
Does not support nested `catch` yet.
"""
function Base.push!(f::FailedAttempts, context)
    stack = current_exceptions()
    n = length(stack)
    n == 0 && throw("Called outside a catch block?")
    if n > 1
        @error("Called within nested catch blocks?")
        for (err, bt) in stack
            showerror(stderr, err, bt)
        end
        throw("Called within nested catch blocks?")
    end
    err, bt = first(stack)
    push!(f.errors, (context, err, bt))
end

function Base.showerror(io::IO, e::FailedAttempts)
    red, bold, reset = crayon"red", crayon"bold", crayon"reset"
    n = length(e.errors)
    several = n > 1
    several && println(io, "All attempts failed:")
    for (i, (desc, err, bt)) in enumerate(e.errors)
        several && println(io, "-"^50)
        several && print(io, "$red$bold[$i/$n]$reset ")
        println("When attempting to $desc:")
        showerror(io, err, bt)
        println(io)
    end
end

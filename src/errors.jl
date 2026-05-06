"""
Use to throw or rethrow when the error is identified within user arguments.
"""
argerr(message, throw = Base.throw) = throw(ArgumentError(message))

"""
Construct this error type when 'asking forgiveness rather than permission' in a row,
and only consider failure if all attempts fail.
This error type will report all failed attempts with their stacktrace.
"""
struct FailedAttempts <: Exception
    errors::Vector # [(attempt description, [(exception, backtrace)])]
    FailedAttempts() = new([])
end
"""
Call within a `catch` block to append failure to the collection.
Provide context completing "attempting to:".
"""
Base.push!(f::FailedAttempts, context) =
    push!(f.errors, (context, current_exceptions()))

function Base.showerror(io::IO, e::FailedAttempts)
    red, bold, reset = crayon"red", crayon"bold", crayon"reset"
    println(io, "All attempts failed:")
    for (i, (desc, exceptions)) in enumerate(e.errors)
        println(io, "-"^50)
        println(io, "$red$bold[$i]$reset When attempting to $desc:")
        for (err, bt) in exceptions
            showerror(io, err, bt)
            println(io)
        end
    end
end

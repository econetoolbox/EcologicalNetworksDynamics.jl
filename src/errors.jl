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
Base.push!(f::FailedAttempts, context) = push!(f.errors, (context, current_exceptions()))

function Base.showerror(io::IO, e::FailedAttempts)
    red, bold, reset = crayon"red", crayon"bold", crayon"reset"
    println(io, "All attempts failed:")
    n = length(e.errors)
    for (i, (desc, exceptions)) in enumerate(e.errors)
        println(io, "-"^50)
        println(io, "$red$bold[$i/$n]$reset When attempting to $desc:")
        for (err, bt) in exceptions
            showerror(io, err, bt)
            println(io)
        end
    end
end

"""
Carefully render arbitrary user input it within error messages,
so that it only takes short space if possible,
or else it is mime-displayed at the bottom,
the 'bottom' being defined by anything we would like to render in-'between'.
"""
function render_input(io, input, between::Function = () -> nothing)
    T = typeof(input)
    type = sprint(show, T)
    short = repr(input)
    if length(short) + length(type) < 80 && !('\n' in short)
        print(io, "\nReceived: $short ::$type")
        between()
    else
        between()
        print(io, "\nReceived: ")
        show(
            io,
            MIME("text/plain");
            context = IOContext(io, :compact => true, :limit => true),
        )
        print(io, "\nType: $type")
    end
end

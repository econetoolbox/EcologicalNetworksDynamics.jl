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
        show(IOContext(io, :compact => true, :limit => true), MIME("text/plain"), input)
        print(io, "\nType: $type")
    end
end

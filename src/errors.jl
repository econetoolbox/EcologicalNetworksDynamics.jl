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

"""
Filter out errors based on the given priority list.
Errors are dropped if *other errors* are higher-ranking.
The rank of an error is the index of its first supertype in the priority list.
Lower index is higher-rank.
"""
function Base.filter!(f::FailedAttempts, priorities::Vector{<:Type})
    # Sort based on rank then drop non-best-ranking ones.
    ranked = map(f.errors) do err
        (_, e, _) = err
        for (i, P) in enumerate(priorities)
            e isa P && return (i, err)
        end
        (0, err) # Unexpected errors don't go silently and rise to the top anyway.
    end
    sort!(ranked; by = first)
    best = ranked |> first |> first
    # Drop all.
    empty!(f.errors)
    # Reintroduce only best-ranking ones.
    for (rank, err) in ranked
        rank == best || return
        push!(f.errors, err)
    end
end

"""
Throw underlying single failed attempt if there is only one.
Otherwise just throw the failed attempt as a whole.
ASSUME the error has a mutable `.mess` field that we can then prefix with the context.
"""
function throw_unwrapped(f::FailedAttempts, throw=Base.throw)
    length(f.errors) > 1 && throw(f)
    (ctx, err, _) = first(f.errors)
    err.mess = "When attempting to $ctx:\n$(err.mess)"
    throw(err)
end

function Base.showerror(io::IO, e::FailedAttempts)
    red, bold, reset = crayon"red", crayon"bold", crayon"reset"
    n = length(e.errors)
    several = n > 1
    several && println(io, "All attempts failed:")
    for (i, (desc, err, bt)) in enumerate(e.errors)
        several && println(io, "-"^50)
        several && println(io, "$red$bold[$i/$n]$reset ")
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

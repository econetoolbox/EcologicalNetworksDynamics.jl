import .Display: yellow, reset

"""
Use to throw or rethrow when the error is identified within user arguments.
"""
argerr(message, throw = Base.throw) = throw(ArgumentError(message))

abstract type OneShotReport end

"""
Use to create apparent one-shot error type,
passing just a closure capturing the environment required for display.
May be 'wrapping' up an underlying source.
"""
mutable struct ErrWith <: OneShotReport
    head::String
    display::Function
    source::Option{Exception}
end
function Base.showerror(io::IO, e::ErrWith)
    (; head, display, source) = e
    println(io, "$yellow$head$reset")
    display(io)
    isnothing(source) || showerror(io, source)
end
errwith(fn::Function, head::String, throw = Base.throw) = throw(ErrWith(head, fn, nothing))
errwrap(fn::Function, src, head::String, rethrow = Base.rethrow) =
    rethrow(ErrWith(head, fn, src)) # Assumed to be usefully rethrow by default.
# If the header is enough context.
errwith(head::String, throw = Base.throw) = throw(ErrWith(head, identity, nothing))
errwrap(src, head::String, rethrow = Base.rethrow) =
    rethrow(ErrWith(head, identity, src))

"""
Newtype `ErrWith` to brand failures.
Supposed to be caught, identified by its brand
then upgraded into something else, not bubble up to toplevel.
"""
macro ErrBrand(Brand)
    Brand = esc(Brand)
    quote
        struct $Brand <: BrandedErrWith
            source::ErrWith
        end
    end
end
abstract type BrandedErrWith <: OneShotReport end
errwith(f::Function, E::Type{<:BrandedErrWith}, h::String, throw = Base.throw) =
    throw(E(ErrWith(h, f, nothing)))
errwrap(f::Function, s, E::Type{<:BrandedErrWith}, h::String, rethrow = Base.rethrow) =
    rethrow(E(ErrWith(h, f, s)))
errwith(E::Type{<:BrandedErrWith}, h::String, throw = Base.throw) =
    throw(E(ErrWith(h, identity, nothing)))
errwrap(s, E::Type{<:BrandedErrWith}, h::String, rethrow = Base.rethrow) =
    rethrow(E(ErrWith(h, identity, s)))

"Prepend context in case of error."
withcontext(ctx::Function, E::Type{<:OneShotReport}, f::Function, args...; kwargs...) =
    try
        f(args...; kwargs...)
    catch e
        e isa E || rethrow(e)
        rethrow(prepend_context!(ctx, e))
    end
withcontext(ctx::Function, f::Function, args...; kwargs...) =
    withcontext(ctx, OneShotReport, f, args...; kwargs...)
function prepend_context!(ctx::Function, e::ErrWith)
    original = e.display
    e.display = io -> begin
        ctx(io)
        original(io)
    end
    e
end
function prepend_context!(ctx::Function, e::BrandedErrWith)
    prepend_context!(ctx, e.source)
    e
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

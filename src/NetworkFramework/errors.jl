
abstract type LibError <: F.InputError end

"""
A simple error type to be raised by component authors regardless of the context.
It'll either be caught/upgraded by the Framework (during expansion)
or by the rest of the generic component code (construction, mutation).
Should [rb]arely reach toplevel on its own once raised although it is ok if this happens.
"""
struct ComponentError <: LibError
    mess::String
end
comperr(m, throw = Base.throw) = throw(ComponentError(m))
Base.showerror(io::IO, e::ComponentError) = print(io, e.mess)

"""
Upgrading from a ComponentError while checking an individual value.
Useful to report standard rendering of the problematic value below the message.
"""
mutable struct ValueError <: LibError
    value::Any
    mess::String
end
valerr(value, mess, throw = Base.throw) = throw(ValueError(value, mess))
function Base.showerror(io::IO, e::ValueError)
    (; value, mess) = e
    print(io, mess)
    render_input(io, value)
end

# Forward error up after upgrading message with additional context.
ComponentError(e::ComponentError, up::Function) = ComponentError(up(e.mess))
ValueError(e::ValueError, up::Function) = ValueError(e.value, up(e.mess))
ValueError(value, e::LibError, up::Function) = ValueError(value, up(e.mess))
fwd_err(up::Function, totry::Function, a...) =
    try
        totry(a...)
    catch e
        e isa LibError && rethrow(typeof(e)(e, up))
        rethrow(e)
    end
# Upgrade to ValueError on the way up.
fwd_err(up::Function, value, totry::Function, a...) =
    try
        totry(a...)
    catch e
        e isa LibError && rethrow(ValueError(value, e, up))
        rethrow(e)
    end

# Same with alternate ergonomics.
try_with(totry::Function, up::Function) =
    try
        totry()
    catch e
        e isa LibError && rethrow(typeof(e)(e, up))
    end
try_with(totry::Function, value, up::Function) =
    try
        totry()
    catch e
        e isa LibError && rethrow(ValueError(value, e, up))
    end

#-------------------------------------------------------------------------------------------
# Special error types for input parsing / conversion error types.
# TODO: only used in convert.jl and lists.jl. Refresh? Move

"""
When analyzing raw user input to produce a value of the desired internal type.
Typically raised during blueprint construction or model field assignment.
"""
abstract type ParseError <: F.InputError end

"""
Error *converting* user input value to target type.
'convert' here means that, like in julia,
an input whose type is already the right type is just aliased.
"""
mutable struct ConvertError <: ParseError
    mess::Option{String} # Typically filled later when upgrading with context.
    input::Any
    target::Type
    reason::Option{String}
end
function Base.showerror(io::IO, e::ConvertError)
    (; mess, input, target, reason) = e
    isnothing(mess) || println(io, "$mess:")
    print(io, "Cannot convert input to `$target`:")
    render_input(io, input, () -> (isnothing(reason) || print(io, "\n$reason")))
end
converr(
    input,
    target::Type,
    reason::Option{String} = nothing,
    context::Option{String} = nothing,
    throw = Base.throw,
) = throw(ConvertError(context, input, target, reason))

"""
A generic kind of parse error, useful during maps / adjacency lists parsing.
"""
mutable struct BaseParseError <: ParseError
    input::Any
    mess::String
    between::Function # Argument to render_input, but takes (io) as argument.
end
const default_between = (io) -> nothing
BaseParseError(input, mess) = BaseParseError(input, mess, default_between)
function Base.showerror(io::IO, e::BaseParseError)
    (; input, mess, between) = e
    print(io, mess)
    render_input(io, input, () -> between(io))
end
parserr(input, mess, throw = Base.throw; between = default_between) =
    throw(BaseParseError(input, mess, between))

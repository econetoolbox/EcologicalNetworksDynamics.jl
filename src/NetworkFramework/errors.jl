# Error raising/upgrading in concordance with the typical data flow.
# Try to leverage the upgrading mechanism for every need,
# the different error types should only be useful to tweak final display.

abstract type LibError <: F.InputError end # <: Useful to be caught during F.add!.

# Useful for the core reason, trusting the above layers to append more context.
struct SimpleError <: LibError
    mess::String
end
liberr(m::String, throw = Base.throw) = throw(SimpleError(m))
Base.showerror(io::IO, e::SimpleError) = print(io, e.mess)

# Useful to report a problematic received value, appended to the end.
mutable struct ValueError <: LibError
    value::Any
    mess::String
end
liberr(value, mess::String, throw = Base.throw) = throw(ValueError(value, mess))
function Base.showerror(io::IO, e::ValueError)
    (; value, mess) = e
    print(io, mess)
    render_input(io, value)
end

# Useful to report conversion problem with expected target type.
mutable struct ConvertError <: LibError
    target::Type
    input::Any
    mess::String
end
liberr(target::Type, input, mess::String, throw = Base.throw) =
    throw(ConvertError(target, input, mess))
function Base.showerror(io::IO, e::ConvertError)
    (; mess, input, target) = e
    print(io, "Cannot convert input to `$target`:\n$mess")
    render_input(io, input)
end

#-------------------------------------------------------------------------------------------
# Upgrade errors using (String -> String) message function adding context.

SimpleError(e::SimpleError, up::Function) = SimpleError(up(e.mess))
ValueError(e::ValueError, up::Function) = ValueError(e.value, up(e.mess))
ConvertError(e::ConvertError, up::Function) = ConvertError(e.target, e.input, up(e.mess))
ValueError(value, e::LibError, up::Function) = ValueError(value, up(e.mess))

# Upgrade and forward error up, same type.
fwd_err(up::Function, totry::Function, args...; kwargs...) =
    try
        totry(args...; kwargs...)
    catch e
        e isa LibError || rethrow(e)
        rethrow(typeof(e)(e, up))
    end

# Same with alternate ergonomics.
try_with(totry::Function, up::Function) =
    try
        totry()
    catch e
        e isa LibError || rethrow(e)
        rethrow(typeof(e)(e, up))
    end

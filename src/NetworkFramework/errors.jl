# Refine framework errors into several error types
# to describe the typical path of an input value from user to the model internals.
# Every step has its own error failure case.
# These are not only meant to be caught by the Framework during component expansion,
# as they may also bubble up to the toplevel if encountered
# in other context than component expansion eg.: blueprint construction, field assignment.
#
#   - raw input (::Any) -> candidate value (::T) : ConvertError
#   - intrinsic check of candidate value : CheckError
#   - check against the whole model : ModelError

# ==========================================================================================
"""
When analyzing raw user input to produce a value of the desired internal type.
Typically raised during blueprint construction or model field assignment.
Implementors are expected to have .input and .mess fields.
"""
abstract type ParseError <: F.InputError end

"""
Error *converting* user input value to target type.
'convert' here means that, like in julia,
an input whose type is already the right type is just aliased.
"""
struct ConvertError <: ParseError
    input::Any
    target::Type
    mess::Option{String}
end
function Base.showerror(io::IO, e::ConvertError)
    (; input, target, mess) = e
    print(io, "Cannot convert input to `$target`.")
    isnothing(mess) || print(io, "\n$mess")
    render_input(io, input)
end
converr(input, target::Type, mess::Option{String} = nothing, throw = Base.throw) =
    throw(ConsistencyError(input, target, mess))

"""
Any other kind of parse error.
"""
struct BaseParseError <: ParseError
    input::Any
    mess::String
    between::Function # Argument to render_input, but takes (io) as argument.
end
const default_between = (io) -> nothing
BaseParseError(input, mess) = BaseParseError(input, mess, default_between)
function Base.showerror(io::IO, e::BaseParseError)
    (; input, mess, between) = e
    print(io, mess)
    render_input(io, input; between = () -> between(io))
end
parserr(input, mess, throw = Base.throw; between = default_between) =
    throw(BaseParseError(input, mess, between))

# ==========================================================================================
"""
Typically raised during blueprint expansion (early check),
blueprint construction or model field assignment.
"""
struct CheckError <: F.InputError
    value::Any
    mess::String
end
function Base.showerror(io::IO, e::CheckError)
    (; value, mess) = e
    print(io, "Invalid value: $mess\nReceived: $(repr(value))")
end
checkerr(value, mess::String, throw = Base.throw) = throw(CheckError(value, mess))

message(e::ParseError) = sprint(showerror, e)
message(e::BaseParseError) = e.mess
message(e::CheckError) = e.mess

# ==========================================================================================
"""
Typically raised during blueprint expansion (late check) or model field assignment.
"""
struct ConsistencyError <: F.InputError
    mess::String
end
Base.showerror(io::IO, e::ConsistencyError) = print(io, e.mess)
conserr(mess::String, throw = Base.throw) = throw(ConsistencyError(mess))

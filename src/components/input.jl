# Shared conversion utils, deviating from Julia's defaults.
# Useful for `check_value` extension when defining typical components.

check(T::Type, input) =
    try
        convert(T, input)
    catch _
        valerr("could not convert to a value of type $T (see stacktrace below)")
    end
check(::Symbol, c::Char) = Symbol(c)
check(::Type{<:Number}, ::Char) =
    valerr("Would not automatically convert Char to a numeric value")

# Non-negative values required.
non_negative(T::Type{<:Number}) = (_view, x) -> non_negative(x)
function non_negative(T, input)
    v = check(T, input)
    v < 0 && valerr("Value cannot be negative")
    v
end

# Pick symbols from an aliased dict.
aliasing_symbol(dict) = (_view, x) -> aliasing_symbol(dict, x)
aliasing_symbol(dict, x) =
    try
        AliasingDicts.standardize(x, dict)
    catch e
        e isa AliasingError &&
            valerr("Invalid reference in aliasing system for $(repr(e.name))", rethrow)
        rethrow(e)
    end

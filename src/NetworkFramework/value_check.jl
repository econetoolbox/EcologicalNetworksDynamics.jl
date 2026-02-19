# Shared conversion utils, deviating from Julia's defaults.
# Useful for `check_value` extension when defining typical components.

import .Dispatchers: valerr

check(T::Type, input) =
    try
        inputconvert(T, input)
    catch _
        valerr("could not convert to a value of type $T")
    end
check(::Symbol, c::Char) = Symbol(c)
check(::Type{<:Number}, ::Char) =
    valerr("Would not automatically convert Char to a numeric value")

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

# Check a symbol am
# check that it is one of the expected symbols,
# emitting a useful error message on invalid symbol
# with the expected list of valid symbols.
function check_symbol(loc, var, list)
    symbols = []
    inputerr() = argerr("Invalid @check_symbol macro use at $loc.\n\
                         Expected a list of symbols. \
                         Got $(repr(list)).")
    list isa Expr || (list = :(($list,)))
    list.head in (:tuple, :vect) || inputerr()
    for s in list.args
        if s isa Symbol
            push!(symbols, s)
        elseif s isa QuoteNode && s.value isa Symbol
            # Allow `:symbol` instead of just `symbol` for less confusion.
            push!(symbols, s.value)
        else
            inputerr()
        end
    end
    exp =
        length(symbols) == 1 ? "$(repr(first(symbols)))" :
        "either $(join(map(repr, symbols), ", ", " or "))"
    symbols = Meta.quot.(symbols)
    symbols = Expr(:tuple, symbols...)
    varsymbol = Meta.quot(var)
    var = esc(var)
    quote
        $var in $symbols ||
            checkfails("Invalid symbol received for '$($varsymbol)': $(repr($var)). \
                        Expected $($exp) instead.")
        true # For use within the @test macro.
    end
end
export @check_symbol


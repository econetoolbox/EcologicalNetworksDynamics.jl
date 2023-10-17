# When optional arguments get sophisticated structure and connections / dependencies
# this helper macro defines primitive local to ease their analysis.
# The following functions get defined,
# they work on a local copy of the given kwargs,
# which gets consumed during the analysis.
#
#  alias!(args::Symbol...)
#    Consider these arguments as aliases:
#    check that no redudant aliased values have been given,
#    and rename/standardize to the first one if given.
#
#  given(arg::Symbol)
#      True if the argument has been provided (be it consumed or not).
#
#  miss = !given
#
#  left(arg::Symbol)
#      True if the argument has been provided but not yet consumed.
#
#  peek(arg::Symbol, type::Type = Any)
#    Get the argument value
#    with helpful error if it cannot be `convert`ed to the given type.
#
#  take!(arg::Symbol, type::Type = Any)
#    Pops the argument value
#    with helpful error if it cannot be `convert`ed to the given type.
#
#  take_or!(arg::Symbol, default, type::Type = typeof(default))
#    Pops the argument value, unless not present and then a default is used.
#    To avoid unnecessary calculations,
#    provide a function as the `default` to calculate the default value,
#    only executed if the argument is not present.
#
#  populate!(defaults...)
#    Complete the arguments with default values, not overriding the originals if given.
#
#  no_unused_arguments()
#    Raise an error if there some arguments have been left unused,
#    indicating possible mispelling or semantic error.
#
#  left()
#    Get reference to underlying consumable dict.
#
# TODO: cover with dedicated test instead of relying on use in the package.
module KwargsHelpers

argerr(mess) = throw(ArgumentError(mess))

macro kwargs_helpers(kwargs)
    (
        kwargs,
        alias!,
        given,
        miss,
        left,
        peek,
        take!,
        take_or!,
        populate!,
        no_unused_arguments,
    ) =
        esc.((
            kwargs,
            :alias!,
            :given,
            :miss,
            :left,
            :peek,
            :take!,
            :take_or!,
            :populate!,
            :no_unused_arguments,
        ))
    quote

        # Copy of the provided kwargs to be consumed.
        kw = Dict{Symbol,Any}($kwargs)
        ks = Set{Symbol}(keys(kw)) # Keep unconsumed for `given`.

        # Consider identical names for these arguments.
        function $alias!(ref::Symbol, aliases::Symbol...)
            aliases = Set(aliases)
            found = nothing
            for k in ks
                k == ref || k in aliases || continue
                if !isnothing(found)
                    a, b = sort([found, k])
                    argerr("Cannot specify both aliases \
                            $(repr(a)) and $(repr(b)) arguments.")
                end
                found = k
            end
            if !isnothing(found) && found != ref
                # Edit references to gloss over the aliases in further calls.
                kw[ref] = pop!(kw, found)
                pop!(ks, found)
                push!(ks, ref)
            end
        end

        # Check whether an argument has been given.
        $given(arg::Symbol) = arg in ks
        $miss(arg::Symbol) = !given(arg)

        # Check whether an argument has not yet been consumed.
        $left(arg::Symbol) = haskey(kw, arg)
        $left() = kw # (or get them all)

        # Abstract over both peek and take!.
        function get(get_fn, arg, type)
            if !$given(arg)
                ty = type === Any ? "" : "::$type"
                argerr("Missing required argument: $arg$ty.")
            end
            $left(arg) ||
                argerr("Argument '$arg' consumed twice: this is a bug in the package.")

            value = get_fn(arg)

            if applicable(convert, type, value)
                try
                    convert(type, value)
                catch
                    argerr("Error when converting argument '$arg' to $type. \
                            (See further down the stacktrace.)")
                end
            else
                argerr("Invalid type for argument '$arg'. \
                        Expected $type, received: $(repr(value)) ::$(typeof(value)).")
            end
        end

        # Retrieve argument value without consuming it.
        $peek(arg::Symbol, type::Type = Any) = get(k -> kw[k], arg, type)

        # Consume argument.
        $take!(arg::Symbol, type::Type = Any) = get(k -> pop!(kw, k), arg, type)

        # Consume argument with a default.
        function $take_or!(arg::Symbol, default, type::Type = typeof(default))
            if $given(arg)
                $take!(arg, type)
            elseif default isa Function
                default()
            else
                default
            end
        end

        # Populate with default args.
        $populate!(; defs...) =
            for (k, v) in defs
                $given(k) && continue
                push!(ks, k)
                kw[k] = v
            end

        # Check that all arguments have been consumed.
        function $no_unused_arguments()
            isempty(kw) && return
            k, v = first(kw)
            argerr("Unexpected argument: $k = $(repr(v)).")
        end

    end
end
export @kwargs_helpers

# Declare here just to satisfy static code analysis.
unerr() = throw("Unimplemented kwarg helper. \
                 Has @kwargs_helpers macro been called in this scope?")
alias!(first, args...) = unerr()
given(arg) = unerr()
miss(arg) = unerr()
left(arg) = unerr()
left() = unerr()
peek(arg, type = nothing) = unerr()
take!(arg, type = nothing) = unerr()
take_or!(arg, default, type = nothing) = unerr()
populate!(; defs...) = unerr()
no_unused_arguments() = unerr()
export alias!
export given
export miss
export left
export peek
export take!
export take_or!
export populate!
export no_unused_arguments

end

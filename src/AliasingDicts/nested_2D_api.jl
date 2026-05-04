# A data structure with two nested aliased dicts
# can be constructed with an interesting "named/aliased 2D" API
# parsing arguments into meaningful bits based on the two aliasing systems.
# For example with an "outer" aliasing system 'O' and an "inner" 'I':
#
#   o_i = 5: means `data[:o][:i] = 5`
#
#   i_o = 5: means `data[:o][:i] = 5` as well (guards against ambiguous names)
#
#   o = (i1 = 5, i2 = 8): means `data[:o][:i1] = 5; data[:o][:i2] = 8`
#
#   i = (o1 = 5, o2 = 8): means `data[:o1][:i] = 5; data[:o2][:i] = 8`
#
#   i = 5 (in a :o context): means `data[:o][:i] = 5`
#
#   o = 5 (in a :i context): means `data[:o][:i] = 5`
#
# A template of expected types for every entry in this 2D structure can be provided.
#
# This file describes the associated parsing logic, guards and error handling.
#
# This is used for the multiplex API and the Allometric rates API.

#-------------------------------------------------------------------------------------------
# Improve error messages by keeping track of the exact way arguments were input.
abstract type Nested2DArg{O<:AD,I<:AD} end # Parametrize with the aliased dict type O{I{T}}.

for T in [
    :BasalArg, # The two parts are explicitly given: `<o>_<i> = ..`.
    :RevBasalArg, # Same in reverse order: `<i>_<o> = ..`.
    :NestedArg, # The inner part is nested: `<o> = (<i> = ..)`.
    :RevNestedArg, # The outer part is nested: `<i> = (<o> = ..)`.
    :OuterContextArg, # The outer is implicit from the context: `<i> = ..`.
    :InnerContextArg, # The inner is implicit from the context: `<o> = ..`.
]
    eval(quote
        struct $T{O,I} <: Nested2DArg{O,I}
            o::Symbol # Outer argument part.
            i::Symbol # Inner argument part.
            $T{O,I}(o, i) where {O,I} = new{O,I}(Symbol(o), Symbol(i))
        end
    end)
end

# Canonicalize nesting order.
reorder(::Type{BasalArg}) = (o, i) -> (o, i)
reorder(::Type{RevBasalArg}) = (i, o) -> (o, i)
reorder(::Type{NestedArg}) = (o, i) -> (o, i)
reorder(::Type{RevNestedArg}) = (i, o) -> (o, i)

# Reconstruct original input to produce useful error messages
original(a::BasalArg) = Symbol("$(a.o)_$(a.i)")
original(a::RevBasalArg) = Symbol("$(a.i)_$(a.o)")
original(a::NestedArg) = (a.o, a.i)
original(a::RevNestedArg) = (a.i, a.o)
original(a::OuterContextArg) = a.i
original(a::InnerContextArg) = a.o
function expand(a::Nested2DArg)
    a = original(a)
    if typeof(a) <: Tuple
        outer, inner = a
        "'$inner' within a '$outer' argument"
    else
        "'$a' argument"
    end
end
export expand

# Error on user input ambiguity.
function ambiguity(nest_name, a::Nested2DArg{O,I}, b::Nested2DArg{O,I}) where {O<:AD,I<:AD}
    o = standardize(a.o, O)
    i = standardize(a.i, I)
    argerr("Ambiguous or redundant specification in aliased 2D input for '$nest_name': \
            '$o' value for '$i' is specified as $(expand(a)), \
            but it has already been specified as $(expand(b)). \
            Consider removing either one.")
end

#-------------------------------------------------------------------------------------------
# Guard against ambiguities in the 2D api.
# (by throwing errors at package *developers*)

# Given an argument name, parse it into all valid (o, i) pairs.
# Return a list of re-ordered (Option{OuterSymbol}, Option{InnerSymbol}, Option{Bool}),
# with the terminal flag defined and raised if reversed.
function arg_parses(arg, ::Type{O}, ::Type{I}) where {O<:AD,I<:AD}
    arg = Symbol(arg)
    orefs = all_references(O)
    irefs = all_references(I)
    # Split on all '_' separators,
    # then collect alls that yield a perfect (o, i) or (i, o) match.
    parses = []
    # Collect trivial, non-combinations first.
    if arg in orefs
        push!(parses, (arg, nothing, nothing))
    end
    if arg in irefs
        push!(parses, (nothing, arg, nothing))
    end
    # Then combination (o, i) and (i, o)
    arg = string(arg)
    bits = split(arg, '_')
    for k in 1:(length(bits)-1)
        a = Symbol(join(bits[1:k], '_'))
        b = Symbol(join(bits[k+1:end], '_'))
        if a in orefs && b in irefs
            push!(parses, (a, b, false))
        end
        if a in irefs && b in orefs
            push!(parses, (b, a, true))
        end
    end
    parses
end

# Turn the result of the above function into something useful for an error message.
function parse_message(
    o::Union{Nothing,Symbol},
    i::Union{Nothing,Symbol},
    ::Type{O},
    ::Type{I},
) where {O<:AD,I<:AD}
    if isnothing(o)
        si = standardize(i, I)
        hi = shortname(I)
        "'$hi::$si'"
    elseif isnothing(i)
        so = standardize(o, O)
        ho = shortname(O)
        "'$ho::$so'"
    else
        so = standardize(o, O)
        si = standardize(i, I)
        ho = shortname(O)
        hi = shortname(I)
        "'$hi::$si' within '$ho::$so'"
    end
end

# Protect against ambiguous arguments splitting.
function ambiguity_guard(arg, nest_name::Symbol, ::Type{O}, ::Type{I}) where {O<:AD,I<:AD}
    parses = arg_parses(arg, O, I)
    if length(parses) > 1
        # There is lexical ambiguity,
        # but no semantic ambiguity if all meanings are the same.
        # Filter out identical meanings
        ((o1, i1),) = parses
        different = Tuple{Option{Symbol},Option{Symbol}}[(o1, i1)]
        for (o, i) in parses
            same = true
            if isnothing(o) != isnothing(o1)
                same = false
            elseif isnothing(i) != isnothing(i1)
                same = false
            elseif !isnothing(o) && standardize(o, O) != standardize(o1, O)
                same = false
            elseif !isnothing(i) && standardize(i, I) != standardize(i1, I)
                same = false
            end
            same || push!(different, (o, i))
        end
        if length(different) > 1
            # This is a true semantic ambiguity.
            (o1, i1), (o2, i2) = different
            throw("Ambiguous aliasing for '$nest_name' 2D API: \
                   argument '$arg' either means \
                   $(parse_message(o1, i1, O, I)) or \
                   $(parse_message(o2, i2, O, I)).")
        end
    end
end

function all_guards(nest_name, ::Type{O}, ::Type{I}) where {O<:AD,I<:AD}

    # 2D input argument names are separated
    # into valid combinations of one or two references.
    # Check for non-ambiguity between both references layers.
    for o in all_references(O), i in all_references(I)
        if o == i
            so = standardize(o, O)
            si = standardize(i, I)
            ho = shortname(O)
            hi = shortname(I)
            throw("Ambiguous aliasing for '$nest_name' 2D API: \
                   argument '$o' either means '$ho::$so' or '$hi::$si'.")
        end
    end

    guard(arg) = ambiguity_guard(arg, nest_name, O, I)

    # Check all possible combinations for ambiguity.
    for arg in all_references(O)
        guard(arg)
    end
    for arg in all_references(O)
        guard(arg)
    end
    for oref in all_references(O), iref in all_references(I)
        guard(Symbol("$(oref)_$(iref)"))
        guard(Symbol("$(iref)_$(oref)"))
    end
end

#---------------------------------------------------------------------------------------
# Parse arguments from input.

# Useful to provide a type template for expected received values.
function multi_promotion(types)
    length(types) == 0 && return Union{}
    length(types) == 1 && return types[1]
    (A, B, rest...) = types
    common = Base.promote_typejoin(A, B)
    for T in rest
        common = Base.promote_typejoin(common, T)
    end
    common
end

# (the `input` given here is typically a `; kwargs...`)
function parse_2D_arguments(
    types,
    make_empty,
    nest_name,
    check,
    input, #  (typically `; kwargs...`)
    ::Type{O},
    ::Type{I};
    # Set if we know either piece of data from the context.
    implicit_outer = nothing,
    implicit_inner = nothing,
) where {O<:AD,I<:AD}

    # Start empty, fill as we collect and check arguments from input.
    (inner_types, all_types) = types
    all_args = make_empty(inner_types)

    # Check whether a value has already been given.
    already(outer, inner) = haskey(all_args[outer], inner)

    # Record in result with ambiguity guard and type check.
    function record(arg, outer, inner, value)
        if already(outer, inner)
            (ex_arg, _) = all_args[outer][inner]
            ambiguity(nest_name, arg, ex_arg)
        else
            T = all_types[outer][inner]
            value = try
                convert(T, value)
            catch
                try
                    T(value)
                catch
                    argerr("Could not convert or adapt input at (:$outer, :$inner) \
                            from $(expand(arg)) with value: $(repr(value)).\n\
                            Expected type   : $(T)\n\
                            Received instead: $(typeof(value))")
                end
            end
            all_args[outer][inner] = (arg, value)
        end
    end

    if isnothing(implicit_outer) && isnothing(implicit_inner)

        # No particular context: the arguments given must specify both parts.
        for (arg, value) in input

            # Match nested specifications first.
            found_nested = false
            for ArgType in [NestedArg, RevNestedArg]
                ro = reorder(ArgType)
                OuterDict, InnerDict = ro(O, I)
                if arg in all_references(OuterDict)
                    found_nested = true
                    # Scroll sub-arguments within the nested specification.
                    # (ask forgiveness not permission here)
                    iterr(e) = begin
                        fname = uppercasefirst(name(OuterDict))
                        nname = name(InnerDict)
                        argerr("$fname argument '$arg' \
                                cannot be iterated as ($nname=value,) pairs: $e")
                    end
                    z = try
                        zip(keys(value), values(value))
                    catch e
                        iterr(e)
                    end
                    for (nested_arg, val) in z
                        typeof(nested_arg) <: Integer && iterr("integer keys.")
                        outer, inner = ro(arg, nested_arg)
                        T = typeof(val)
                        nested = ArgType{O,I}(outer, inner)
                        record(nested, outer, inner, val)
                    end
                end
                if found_nested
                    break
                end
            end
            if found_nested
                continue
            end

            # Otherwise, match basal specification with parameter of the form <outer>_<inner>.
            splits = arg_parses(arg, O, I)
            if length(splits) == 0
                oname, iname = name.((O, I))
                argerr("Could not recognize '$oname' or '$iname' \
                        within argument name '$arg'.")
            end

            # There may be several matches,
            # but development ambiguity guards guarantee only one meaning.
            ((outer, inner, reversed),) = splits
            T = typeof(value)
            basal = (reversed ? RevBasalArg{O,I} : BasalArg{O,I})(outer, inner)
            record(basal, outer, inner, value)

        end

        # If context is given, then parsing is simpler since nesting is disallowed.
    elseif isnothing(implicit_outer)
        standardize(implicit_inner, I) # Guard against invalid implicit ref.
        for (outer, value) in input
            T = typeof(value)
            arg = InnerContextArg{O,I}(outer, implicit_inner)
            record(arg, outer, implicit_inner, value)
        end

    elseif isnothing(implicit_inner)
        standardize(implicit_outer, O) # Guard agains invalid implicit ref.
        for (inner, value) in input
            T = typeof(value)
            arg = OuterContextArg{O,I}(implicit_outer, inner)
            record(arg, implicit_outer, inner, value)
        end

    else
        oname, iname = name.((O, I))
        argerr("Cannot specify both implicit '$iname' ($(repr(implicit_inner))) \
                and implicit '$oname' ($(repr(implicit_outer))).")
    end

    # Check arguments further depending on the nested logic.
    check(all_args, implicit_outer, implicit_inner)

    all_args

end

# In restricted "1D" context, remove unnecessary dict nesting in the result.
function parse_outer_arguments_with_context(
    inner,
    types,
    make_empty,
    nest_name,
    check,
    input,
    ::Type{O},
    ::Type{I};
) where {O<:AD,I<:AD}
    all_args = parse_2D_arguments(
        types,
        make_empty,
        nest_name,
        check,
        input,
        O,
        I;
        implicit_inner = inner,
    )
    # Calculate common type in this context.
    (_, all_types) = types
    T = multi_promotion(all_types[o][inner] for o in standards(O))
    res = O{Tuple{Nested2DArg{O,I},T}}()
    for (k, v) in all_args
        haskey(v, inner) && (res[k] = v[inner])
    end
    res
end
function parse_inner_arguments_with_context(
    outer,
    types,
    make_empty,
    nest_name,
    check,
    input,
    ::Type{O},
    ::Type{I};
) where {O<:AD,I<:AD}
    all_args = parse_2D_arguments(
        types,
        make_empty,
        nest_name,
        check,
        input,
        O,
        I;
        implicit_outer = outer,
    )
    all_args[outer]
end

# Check that there is no aliasing/combination conflicts
# and generate convenience parsing function/types
# dedicated to one particular 2D combination.
# Requires that check_<name>_arguments be defined.
# Requires that <name>_types be defined as a type template for all values.
# (see example uses in tests)
function define_2D_api(mod::Module, name::Symbol, O::Type{<:AD}, I::Type{<:AD})
    all_guards(name, O, I)

    # The following items are mostly generated from short names.
    # This requires a nested `eval`
    # because eg. `shortname(O)` cannot be evaluated during macro expansion.
    lname = Symbol(lowercase(String(name)))
    oshort = shortname(O)
    ishort = shortname(I)
    Oshort, Ishort = Symbol.(pascalcase.(string.((oshort, ishort))))
    Input = Symbol(name, :Input)
    TrackedValue = Symbol(name, :TrackedValue)
    TrackedInnerDict = Symbol(:Tracked, Ishort, :Dict)
    Arguments = Symbol(name, :Arguments)
    NestedDict = Symbol(name, :Dict)
    types = Symbol(lname, :_types)
    make_empty = Symbol(:empty_, lname, :_args)
    parse = Symbol(:parse_, lname, :_arguments)
    check = Symbol(:check_, lname, :_arguments)
    parse_outer = Symbol(:parse_, oshort, :_for_, ishort)
    parse_inner = Symbol(:parse_, ishort, :_for_, oshort)

    # Calculate common types per sub-dict.
    types = mod.eval(types)
    inner_common_types =
        O{DataType}((k => multi_promotion(values(sub)) for (k, sub) in types)...)
    types = (inner_common_types, types)

    # Types, aliases and new exposed methods definition within the caller chosen module.
    sname = Meta.quot(name)
    MI = methname(I)
    MO = methname(O)
    mod.eval(
        quote
            # Alias the basic nested (untracked) dict
            # and specify an outer builder for it.
            const $NestedDict{T} = $O{$I{T}}

            # The values returned from arguments parsing
            # also contains the original arguments input to improve error messages.
            # Value possibly set to 'nothing' downstream.
            const $Input = $Option{$Nested2DArg{$O,$I}}
            # Value + original input argument.
            const $TrackedValue{T} = $Tuple{$Input,T}
            # All tracked internal values.
            const $TrackedInnerDict{T} = $I{$TrackedValue{T}}
            # All tracked nested values.
            const $Arguments = $O{$I}

            # Missing entries correspond to entries not specified as input.
            # They can be filled with `nothing` values downstream.
            # All entries start missing.
            $make_empty(inner_types) = $Arguments(
                (
                    o_key => $TrackedInnerDict{inner_types[o_key]}() for
                    o_key in $standards($O)
                )...,
            )

            # Construct plain inner dict from tracked one.
            function $MI{T}(parsed::$TrackedInnerDict) where {T}
                $I{T}((i => value for (i, (_, value)) in parsed)...)
            end

            # Parse directly from kwargs input.
            function $NestedDict{T}(; kwargs...) where {T}
                parsed = $parse(kwargs)
                $NestedDict{T}(parsed)
            end

            # Remove arguments tracking information.
            function $NestedDict{T}(parsed::$Arguments) where {T}
                $NestedDict{T}(
                    (
                        o => $I{T}((i => value for (i, (_, value)) in sub)...) for
                        (o, sub) in parsed
                    )...,
                )
            end

            # Leave a hook to the check function to widen possible use cases.
            $parse(
                input;
                implicit_outer = nothing,
                implicit_inner = nothing,
                check = $check,
            ) = $parse_2D_arguments(
                $types,
                $make_empty,
                $sname,
                check,
                input,
                $O,
                $I;
                implicit_outer,
                implicit_inner,
            )

            $parse_outer(inner, input; check = $check) =
                $parse_outer_arguments_with_context(
                    inner,
                    $types,
                    $make_empty,
                    $sname,
                    check,
                    input,
                    $O,
                    $I,
                )

            $parse_inner(outer, input; check = $check) =
                $parse_inner_arguments_with_context(
                    outer,
                    $types,
                    $make_empty,
                    $sname,
                    check,
                    input,
                    $O,
                    $I,
                )

            # Display for the nested dict (no need to name the two levels).
            function $(methname(display_short))(d::$NestedDict)
                (; display_short, shortest) = $AliasingDicts
                D = typeof(d)
                "($(join(("$(shortest(o, D)): $(display_short(sub))"
                          for (o, sub) in d), ", ")))"
            end

            function $(methname(display_long))(d::$NestedDict; level = 0)
                isempty(d) && return "()"
                (; aliases) = $AliasingDicts
                ind(n) = "\n" * repeat("  ", level + n)
                res = "("
                # Only remind the aliases for the first times sub entry appear.
                sub_appeared = Set()
                for (oref, als) in aliases(d)
                    haskey(d, oref) || continue
                    sub = d[oref]
                    res *= ind(1) * "$oref ($(join(repr.(als), ", "))) => ("
                    if isempty(sub)
                        res *= ")"
                        continue
                    end
                    for (iref, als) in aliases(sub)
                        haskey(sub, iref) || continue
                        if iref in sub_appeared
                            als = ""
                        else
                            als = " ($(join(repr.(als), ", ")))"
                            push!(sub_appeared, iref)
                        end
                        v = sub[iref]
                        res *= ind(2) * "$iref$als => $v"
                    end
                    res *= ind(1) * ")"
                end
                res * ind(0) * ")"
            end

            function $(methname(show))(io::IO, d::$NestedDict{T}) where {T}
                print(io, "$(typeof(d))$($display_short(d))")
            end

            function $(methname(show))(
                io::IO,
                ::MIME"text/plain",
                d::$NestedDict{T},
            ) where {T}
                print(io, "$(typeof(d))$($display_long(d))")
            end

        end,
    )
end
export define_2D_api

# Convenience macro for defining methods and properties.
#
# Invoker defines the behaviour in a function code and then calls:
#
#   @method function_name depends(components...) read_as(names...) # or write_as(names...)
#
# Or alternately:
#
#   @method begin
#       function_name
#       depends(components...)
#       read_as(property_names...) # or write_as(property_names...)
#   end
macro method(input...)

    # Push resulting generated code to this variable.
    res = quote end
    push_res!(xp) = xp.head == :block ? append!(res.args, xp.args) : push!(res.args, xp)

    # Raise *during expansion* if parsing fails.
    perr(mess) = throw(ItemMacroParseError(:method, __source__, mess))

    # Raise *during execution* if the macro was invoked with inconsistent input.
    # (assuming `fn` generated variable has been set)
    src = Meta.quot(__source__)
    push_res!(quote
        fn = nothing # Refined later.
        xerr = (mess) -> throw(ItemMacroExecError(:method, fn, $src, mess))
    end)

    # Convenience wrap.
    tovalue(xp, ctx, type) = to_value(__module__, xp, ctx, :xerr, type)
    tocomptype(xp, ctx) = to_component_type(__module__, xp, :ValueType, ctx, :xerr)

    #---------------------------------------------------------------------------------------
    # Parse macro input,
    # while also generating code checking invoker input within invocation context.

    # Unwrap input if given in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    li = length(input)
    if li == 0 || li > 3
        perr(
            "$(li == 0 ? "Not enough" : "Too much") macro input provided. Example usage:\n\
             | @method begin\n\
             |      function_name\n\
             |      depends(...)\n\
             |      read_as(...)\n\
             | end\n",
        )
    end

    # The first section needs to specify the function containing adequate behaviour code.
    # Since an additional method to this function needs to be generated,
    # then the input expression must be a plain symbol or Path.To.symbol,
    # unless there is another programmatic way
    # to add a method to a function in julia.
    fn_xp = input[1]
    fn_xp isa Symbol ||
        fn_xp isa Expr && fn_xp.head == :. ||
        perr("Not a method identifier or path: $(repr(fn_xp)).")
    push_res!(quote

        fn = $(tovalue(fn_xp, "System method", Function))

        # Attempt to infer the system value type from the first argument if unambiguous.
        args = unique(Iterators.map(methods(fn)) do m
            parms = m.sig.parameters
            length(parms) > 1 ? parms[2] : nothing
        end)

        # Okay to drop methods without arguments.
        args = filter(!isnothing, args)
        n = length(args)
        if n == 0
            xerr("No method of '$fn' take at least one argument.")
        elseif n == 1
            ValueType = first(args)
        elseif n == 2 && args[2] == System{args[1]}
            # Special-case args == [System{T}, T], which happens
            # if methods have been added to 'fn' after a first @method invocation.
            ValueType = args[1]
        elseif n == 2 && args[1] == System{args[2]}
            ValueType = args[2]
        else
            ValueType = nothing
        end

        # Consider as un-inferred if Any.
        ValueType == Any && (ValueType = nothing)

    end)

    # Next come other optional specifications in any order.
    deps_xp = nothing # Evaluates to [components...]
    proptype = nothing
    propsymbols = []
    read_kw, write_kw = (:read_as, :write_as)
    kw = nothing

    for i in input[2:end]

        # Dependencies section: specify the components required to use the method.
        @capture(i, depends(list__))
        if !isnothing(list)
            isnothing(deps_xp) || perr("The `depends` section is specified twice.")
            deps_xp = :([])
            first = true
            for dep in list
                if first
                    # Infer the value type from the first dep if possible.
                    xp = quote
                        dep = $(tovalue(dep, "First dependency", Type))
                        dep <: Blueprint || xerr(
                            "First dependency: expression does not evaluate \
                             to a blueprint type, but to '$dep' ($($(repr(dep)))).",
                        )
                        if isnothing(ValueType)
                            ValueType = system_value_type(dep)
                        else
                            if !(dep <: Blueprint{ValueType})
                                actual_V = system_value_type(dep)
                                xerr("Depends section: system value type \
                                      has been inferred to be '$ValueType' \
                                      based on the first parameter type(s) of '$fn', \
                                      but '$dep' subtypes '$(Blueprint{actual_V})' \
                                      and not '$(Blueprint{ValueType})'.")
                            end
                        end
                        dep
                    end
                    first = false
                else
                    xp = tocomptype(dep, "Depends section")
                end
                push!(deps_xp.args, xp)
            end
            continue
        end

        # Property section: specify whether the code can be accessed as a property.
        @capture(i, kw_(propnames__))
        if !isnothing(kw)
            if Base.isidentifier(kw)
                if !(kw in (read_kw, write_kw))
                    perr("Invalid section keyword: $(repr(kw)). \
                          Expected `$read_kw` or `$write_kw` or `depends`.")
                end
                if !isnothing(proptype)
                    proptype == kw && perr("The `$kw` section is specified twice.")
                    perr("Cannot specify both `$proptype` section and `$kw`.")
                end
                for pname in propnames
                    pname isa Symbol ||
                        perr("Property name is not a simple identifier: $(repr(pname)).")
                end
                propsymbols = Meta.quot.(propnames)
                proptype = kw
                continue
            end
        end

        perr("Unexpected @method section. \
              Expected `depends(..)`, `$read_kw(..)` or `$write_kw(..)`. \
              Got: $(repr(i)).")

    end

    if isnothing(deps_xp)
        deps_xp = :([])
    end

    if isempty(deps_xp.args)
        push_res!(
            quote
                isnothing(ValueType) && xerr("Without dependencies given, \
                                              the system value type could not be inferred \
                                              from the first parameter type of '$fn'. \
                                              Consider making it explicit.")
            end,
        )
    end

    # Check that consistent 'depends' component types have been specified.
    push_res!(
        quote
            deps = Set()
            raw = $deps_xp

            # Now that we have a guarantee that 'ValueType' has been completely inferred,
            # use it to guard against redundant method specifications.
            (specified_as_method(ValueType, fn) && !REVISING) &&
                xerr("Function '$fn' already marked as a method \
                      for '$(System{ValueType})'.")

            for dep in raw
                for already in deps
                    vertical_guard(
                        dep,
                        already,
                        () -> xerr("Dependency '$dep' is specified twice."),
                        (sub, sup) ->
                            xerr("Dependency '$sub' is also specified as '$sup'."),
                    )
                end
                push!(deps, dep)
            end
        end,
    )

    if kw == read_kw
        push_res!(quote
            try
                which(fn, Tuple{ValueType})
            catch
                xerr("The function '$fn' cannot be called \
                      with exactly 1 argument of type '$ValueType' \
                      as required to be set as a 'read' property.")
            end
        end)
    end

    if kw == write_kw
        push_res!(
            quote
                # The assesment is trickier here
                # since there may be a constraint on the second argument,
                # although there is no restriction which constraint,
                # so which(fn, Tuple{ValueType,Any}) would incorrectly fail.
                # The best I've found then is to scroll all methods
                # until we find a match for the desired signature.
                # Maybe there is a better way to do this in julia?
                match = any(Iterators.map(methods(fn)) do m
                    parms = m.sig.parameters
                    length(parms) == 3 && ValueType <: parms[2]
                end)
                if !match
                    xerr("The function '$fn' cannot be called with exactly 2 arguments, \
                          the first one being of type '$ValueType', \
                          as required to be set as a 'write' property.")
                end
            end,
        )
    end

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information should have been parsed and checked,
    # both at expansion time and generated code execution time.
    # The only remaining code to generate work is just the code required
    # for the system to work correctly.

    # Generate dependencies method.
    push_res!(quote
        Framework.depends(::Type{ValueType}, ::Type{typeof(fn)}) = deps
    end)

    # Generate the method checking that required components
    # are loaded on the system instance.
    push_res!(
        quote
            function Framework.missing_dependency_for(
                ::Type{ValueType},
                M::Type{typeof(fn)},
                s::System,
            )
                for dep in depends(ValueType, M)
                    has_component(s, dep) || return dep
                end
                nothing
            end
        end,
    )

    # But generate the checked method for the system.
    efn = LOCAL_MACROCALLS ? esc(fn_xp) : :($__module__.$fn_xp)
    fn_path = Meta.quot(fn_xp)
    push_res!(
        quote
            # TODO: generating it this way results in users encountering
            # ambiguities when calling `fn(system, other_arg)`,
            # and the only way out is to have them explicitly type the first argument.
            # This is unfortunate, but I've found no way of disambiguating this
            # from the macro alone..
            # unless there is a proper way to create `Method`s dynamically?
            function $efn(s::System{ValueType}, args...; kwargs...)
                dep = missing_dependency_for(ValueType, fn, s)
                if !isnothing(dep)
                    a = isabstracttype(dep) ? " a" : ""
                    throw(MethodError(ValueType, $fn_path, "Requires$a component '$dep'."))
                end
                fn(s._value, args...; kwargs...)
            end
            # TODO: if unexistent, then
            # defining a fallback `fn(value, args...; _system=s, kwargs...)` method here
            # would enable that implementors of `fn` take decisions
            # depending on the whole system value, and components currently available.
            # In particular, it would avoid the need
            # to define both `_simulate` and `simulate` in the exposed lib.
        end,
    )

    # Property specification.
    # (for getproperty(s::System, ..))
    if !isnothing(proptype)
        set = (proptype == read_kw) ? :set_read_property! : :set_write_property!
        # TODO: check property availability *before* setting it,
        # otherwise the components type system ends up in a broken state
        # when the following fails.
        propsymbols = map(s -> first(s.args), propsymbols)
        push_res!(quote
            for psymbol in $[propsymbols...]
                $set(ValueType, psymbol, fn)
            end
        end)
    end

    res
end
export @method

# Check whether the function has already been specified as a @method.
# (it has been if there is a dedicated `depends` method for it)
specified_as_method(V::Type, fn::Function) =
    which(Framework.depends, Tuple{Type{V},Type{typeof(fn)}}).sig.parameters[3] ===
    Type{typeof(fn)}

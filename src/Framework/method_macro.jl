# Convenience macro for defining a new system method and possible associated properties.
#
# Invoker defines the behaviour in a function code containing at least one 'receiver':
# an argument explicitly typed with the system wrapped value.
#
#   f(v::Value, ...) = <invoker code>
#
# Then, the macro invokation goes like:
#
#   @method f depends(components...) read_as(names...) # or write_as(names...)
#
# Or alternately:
#
#   @method begin
#       function_name # or function_name{ValueType} if inference fails.
#       depends(components...)
#       read_as(property_names...) # or write_as(property_names...)
#   end
#
# This will generate additional methods to `f`
# so it accepts `System{Value}` instead of `Value` as the receiver.
# These wrapper methods check that components dependencies are met
# before forwarding to the original method.
#
# If an original method has the exact:
#  - `f(receiver)` signature, then it can be marked as a `read` property.
#  - `f(receiver, rhs)` signature, then it can be marked as a `write` property.
#
# Sometimes, the method needs to take decision
# depending on other system components that are not strict dependencies,
# so the whole system needs to be queried and not just the wrapped value.
# In this case, the invoker adds a 'hook' `::System` parameter to their signature:
#
#   f(v, a, b, _system::System) = ...
#
# The generated wrapper method then elides this extra 'hook' argument,
# but still forwards the whole system to it:
#
#   f(s::System{ValueType}, a, b) = f(value(s), a, b, s) # (generated)
#
# Two types of items can be listed in the 'depends' section:
#  - Component: means that the generated methods
#    will guard against use with system missing it.
#  - Another method: means that the generated methods
#    will guard against use with systems failing to meet requirements for this other method.

macro method(input...)
    mod = __module__
    src, input = Meta.quot.((__source__, input))
    quote
        $method_macro($mod, $src, $input)
        nothing
    end
end
export @method

function method_macro(mod, src, input)

    # Raise on failure.
    item_err(mess, item) = throw(ItemMacroError(:method, item, src, mess))
    new_fn = Ref{Option{Function}}(nothing) # Refine later.
    err(mess) = item_err(mess, new_fn[])

    mod, input = parse_module(mod, input...)

    # Convenience wrap.
    ValueType = Ref{Union{Nothing,DataType}}(nothing)
    ceval(xp, ctx, type) = checked_eval(mod, xp, ctx, err, type)
    evaldep_infer(xp, ctx) = eval_dependency(mod, xp, ctx, err)
    evaldep(xp, ctx) = eval_dependency(mod, xp, ValueType[], ctx, err)

    #---------------------------------------------------------------------------------------
    # Parse and check macro input.

    # Unwrap input if given in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    li = length(input)
    if li == 0 || li > 3
        err("$(li == 0 ? "Not enough" : "Too much") macro input provided. Example usage:\n\
             | @method begin\n\
             |      function_name\n\
             |      depends(...)\n\
             |      read_as(...)\n\
             | end\n")
    end

    # The first section needs to specify the function containing adequate behaviour code.
    xp = input[1]
    (false) && (local fn, V) # (reassure JuliaLS)
    @capture(xp, fn_{V_} | fn_)
    ValueType[] = isnothing(V) ? nothing : ceval(V, "System value type", Type)
    new_fn[] = ceval(fn, "System method", Function)
    fn = new_fn[]

    # Next come other optional specifications in any order.
    deps = nothing # Evaluates to [components...]
    proptype = nothing
    prop_paths = []
    read_kw, write_kw = (:read_as, :write_as)
    prop_kw = nothing

    for i in input[2:end]

        # Dependencies section: specify the components required to use the method.
        (false) && (local list) # (reassure JuliaLS)
        @capture(i, depends(list__))
        if !isnothing(list)
            isnothing(deps) || err("The `depends` section is specified twice.")
            deps = []
            first = true
            for dep in list
                dep = if first
                    first = false
                    # Infer the value type from the first dep if possible.
                    dep = evaldep_infer(dep, "First dependency")
                    if isnothing(ValueType[])
                        # Need to infer.
                        ValueType[] = if dep isa Function
                            vals = method_for_values(typeof(dep))
                            length(vals) == 1 ||
                                err("First dependency: the function specified \
                                     has been recorded as a method for \
                                     [$(join(vals, ", "))]. \
                                     It is ambiguous which one the focal method \
                                     is being defined for.")
                            Base.first(vals)
                        else
                            C = dep # Then it must be a component.
                            system_value_type(C)
                        end
                    else
                        V = ValueType[]
                        if dep isa Function
                            specified_as_method(V, typeof(dep)) ||
                                err("Depends section: system value type \
                                     is supposed to be '$V' \
                                     based on the first macro argument, \
                                     but '$dep' has not been recorded \
                                     as a system method for this type.")
                        else
                            C = dep
                            if !(C <: Component{V})
                                C_V = system_value_type(C)
                                err("Depends section: system value type \
                                     is supposed to be '$V' \
                                     based on the first macro argument, \
                                     but $C subtypes '$Component{$C_V}' \
                                     and not '$Component{$V}'.")
                            end
                        end
                    end
                    dep
                else
                    evaldep(dep, "Depends section")
                end
                push!(deps, dep)
            end
            continue
        end

        # Property section: specify whether the code can be accessed as a property.
        (false) && (local paths) # (reassure JuliaLS)
        @capture(i, prop_kw_(paths__))
        if !isnothing(prop_kw)
            if Base.isidentifier(prop_kw)
                if !(prop_kw in (read_kw, write_kw))
                    err("Invalid section keyword: $(repr(prop_kw)). \
                         Expected :$read_kw or :$write_kw or :depends.")
                end
                if !isnothing(proptype)
                    proptype == prop_kw && err("The :$prop_kw section is specified twice.")
                    err("Cannot specify both :$proptype section and :$prop_kw.")
                end
                for path in paths
                    is_identifier_path(path) || err("Property name is not a simple \
                                                     identifier path: $(repr(path)).")
                end
                prop_paths = paths
                proptype = prop_kw
                continue
            end
        end

        err("Unexpected @method section. \
             Expected `depends(..)`, `$read_kw(..)` or `$write_kw(..)`. \
             Got instead: $(repr(i)).")

    end

    isnothing(deps) && (deps = [])

    if isempty(deps)
        isnothing(ValueType[]) && err("The system value type cannot be inferred \
                                       when no dependencies are given.\n\
                                       Consider making it explicit \
                                       with the first macro argument: \
                                       `$fn{MyValueType}`.")
    end
    ValueType = ValueType[]

    #---------------------------------------------------------------------------------------
    # All required information collected from input. Processing.

    # Split paths into (path, target, property_name)
    prop_paths = map(prop_paths) do path
        P = super(property_space_type(path, ValueType))
        last = last_in_path(path)
        (path, P, last)
    end

    # Scroll existing methods to find the ones to wrap
    # with methods receiving 'System' values as parameters.
    # Collect information regarding every method to wrap: [(
    #   method: to be wrapped in a new checked method receiving `System`,
    #   types: list of positional parameters types,
    #   names: list of positional parameters names,
    #   receiver: the receiver parameter name,
    #   hook: the receiver parameter name,
    # )]
    to_wrap = []
    can_be_read_property = Ref(false)
    can_be_write_property = Ref(false)
    for mth in methods(fn)

        # Retrieve fixed-parameters types for the method.
        parms = collect(mth.sig.parameters[2:end])
        isempty(parms) && continue
        # Retrieve their names.
        # https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4?u=iago-lito
        names = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), mth.slot_syms)[2:end]

        # Among them, find the one to use as the system 'receiver',
        # and the possible one to use as the 'hook'.
        values = Set()
        system_values = Set()
        systems_only = Set()
        for (i, (p, n)) in enumerate(zip(parms, names))
            p isa Core.TypeofVararg && continue
            if n == Symbol("#unused#")
                # May become used in the generated method
                # if it turns out to be a receiver: needs a name to refer to.
                n = Symbol('#', i)
                names[i] = n
            end
            if p <: ValueType
                push!(values, n)
            elseif p <: PropertySpace
                system_value_type(p) === ValueType && push!(values, n)
            end
            p <: System{ValueType} && push!(system_values, n)
            p === System && push!(systems_only, n)
        end
        severr =
            (what, set, type) -> err("Receiving several (possibly different) $what \
                                      is not yet supported by the framework. \
                                      Here both parameters :$(pop!(set)) and :$(pop!(set)) \
                                      are of type $type.")
        length(values) > 1 && severr("system/values parameters", values, ValueType)
        isempty(values) && continue
        receiver = pop!(values)
        sv = system_values
        length(sv) > 1 && severr("system hooks", sv, System{ValueType})
        hook = if isempty(system_values)
            so = systems_only
            length(so) > 1 && severr("system hooks", so, System)
            isempty(so) ? nothing : pop!(so)
        else
            pop!(system_values)
        end

        n_parms_for_user = length(parms) - !isnothing(hook)
        if !isnothing(prop_kw)
            if n_parms_for_user == 1
                can_be_read_property[] = true
            elseif n_parms_for_user == 2 &&
                   (parms[1] <: ValueType || hook == first(names) && parms[2] <: ValueType)
                can_be_write_property[] = true
            end
        end

        # Record for wrapping.
        push!(to_wrap, (mth, parms, names, receiver, hook))
    end
    isempty(to_wrap) &&
        err("No suitable method has been found to mark $fn as a system method. \
             Valid methods must have at least \
             one 'receiver' argument of type ::$ValueType.")

    # Use 'ValueType' to guard against redundant method specifications.
    (specified_as_method(ValueType, typeof(fn)) && !REVISING) &&
        err("Function '$fn' already marked as a method for systems of '$ValueType'.")

    # Check that consistent 'depends' component types have been specified.
    # Expand method dependencies into the corresponding components.
    # Redundancy (including vertical ones)
    # are allowed in this context.
    raw_deps = deps
    deps = OrderedSet{CompType{ValueType}}()
    for rdep in raw_deps
        subdeps = if rdep isa Function
            depends(System{ValueType}, typeof(rdep))
        else
            [rdep]
        end
        for newdep in subdeps
            # Don't add to dependencies if an abstract supercomponent
            # is already listed, and remove dependencies
            # as more abstract supercomponents are found.
            has_sup = false
            for already in deps
                if newdep <: already
                    has_sup = true
                    break
                end
                if already <: newdep
                    pop!(deps, already)
                    break
                end
            end
            if !has_sup
                push!(deps, newdep)
            end
        end
    end

    if prop_kw == read_kw
        can_be_read_property[] || err("The function cannot be called with exactly \
                                        1 argument of type '$ValueType' \
                                        as required to be set as a 'read' property.")
    end

    if prop_kw == write_kw
        can_be_write_property[] ||
            err("The function cannot be called with exactly 2 arguments, \
                 the first one being of type '$ValueType', \
                 as required to be set as a 'write' property.")
    end

    # Check properties availability.
    if prop_kw == read_kw
        for (path, P, pname) in prop_paths
            has_read_property(P, Val(pname)) &&
                err("The property $(repr(path)) is already defined for target '$P'.")
        end
    else
        for (path, P, pname) in prop_paths
            has_read_property(P, Val(pname)) ||
                err("The property $(repr(path)) cannot be marked 'write' \
                     without having first been marked 'read' \
                     for target '$P'.")
            has_write_property(P, Val(pname)) &&
                err("The property $(repr(path)) is already marked 'write' \
                     for target '$P'.")
        end
    end

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information
    # should have been parsed, evaluated and checked.
    # The only remaining code to generate and evaluate
    # is the code required for the system to work correctly.

    # Generate dependencies method.
    Fn = Type{typeof(fn)}
    Target = System{ValueType}
    eval(quote
        Framework.depends(::Type{$Target}, ::$Fn) = $deps
    end)

    # Wrap the detected methods within checked methods receiving 'System' values.
    for (mth, parms, pnames, receiver, hook) in to_wrap
        # Start from dummy (; kwargs...) signature/forward call..
        # (hygienic temporary variables, generated for the target module)
        dep, a = gensym.((:dep, :a))
        xp = quote
            function (::typeof($fn))(; kwargs...)
                $dep = first_missing_dependency_for($fn, $system($receiver))
                if !isnothing($dep)
                    $a = isabstracttype($dep) ? " a" : ""
                    throw(
                        MethodError(
                            $ValueType,
                            nameof($fn),
                            "Requires$($a) component $($dep).",
                        ),
                    )
                end
                $fn(; kwargs...)
            end
        end
        # .. then fill them up from the collected names/parameters.
        parms_xp = xp.args[2].args[1].args #  (the `(; kwargs)` in signature)
        args_xp = xp.args[2].args[2].args[end].args # (the same in the call)
        for (name, type) in zip(pnames, parms)
            parm, arg = if type isa Core.TypeofVararg
                # Forward variadics as-is.
                (:($name::$(type.T)...), :($name...))
            else
                if name == receiver
                    # Dispatch signature on the target
                    # to transmit the inner value to the call.
                    (:($name::$Target), :(value($name)))
                elseif name == hook
                    # Don't receive at all, but transmit from the receiver.
                    (nothing, :(system($receiver)))
                else
                    # All other arguments are forwarded as-is.
                    (:($name::$type), name)
                end
            end
            isnothing(parm) || push!(parms_xp, parm)
            push!(args_xp, arg)
        end
        eval(xp)
    end

    # Property specification.
    # (for getproperty(s::System, ..))
    if !isnothing(proptype)
        set = (proptype == read_kw) ? set_read_property! : set_write_property!
        for (_, P, pname) in prop_paths
            set(P, pname, fn)
        end
    end

    # Record as specified to avoid it being recorded again.
    eval(quote
        $Framework.specified_as_method(::Type{$ValueType}, ::$Fn) = true
    end)
    vals = method_for_values(typeof(fn))
    if isempty(vals)
        # Specialize for this freshly created value.
        eval(quote
            $Framework.method_for_values(::$Fn) = $vals
        end)
    end
    push!(vals, ValueType) # Append the new one in any case.

end

# Check whether the function has already been specified as a @method
# for this system value type.
specified_as_method(::Type, ::Type{<:Function}) = false
# Reverse-map.
method_for_values(::Type{<:Function}) = DataType[]

# Check for either a component or an alternate method.
function eval_dependency(mod, xp, V, ctx, err)
    dep = checked_eval(mod, xp, ctx, err, Any)
    if dep isa Function
        specified_as_method(V, typeof(dep)) ||
            err("$ctx: the function specified as a dependency \
                 has not been recorded as a system method for '$V':$(xpres(xp, dep))")
        dep
    else
        check_component_type_or_instance(xp, dep, V, ctx, err)
    end
end

# Version without an expected value type.
function eval_dependency(mod, xp, ctx, err)
    dep = checked_eval(mod, xp, ctx, err, Any)
    if dep isa Function
        vals = method_for_values(typeof(dep))
        isempty(vals) && err("$ctx: the function specified as a dependency has not \
                              been recorded as a system method:$(xpres(xp, dep))")
        dep
    else
        check_component_type_or_instance(xp, dep, ctx, err)
    end
end

# Call later to append aliases.
# TODO: this is only tested by the above client package yet. Test within framework tests.
macro alias(old, new, V)
    old, new = Meta.quot.((old, new))
    quote
        $alias_property!($old, $new, $V)
    end
end
export @alias
function alias_property!(a, b, V)
    # Extract original.
    (A, B) = property_space_type.((a, b), (V,))
    (Pa, Pb) = super.((A, B))
    (na, nb) = last_in_path.((a, b))
    fn_a = read_property(Pa, Val(na)) # Checked.
    fn_a! = possible_write_property(Pa, Val(na))
    set_read_property!(Pb, nb, fn_a)
    isnothing(fn_a!) && return
    set_write_property!(Pb, nb, fn_a!)
end

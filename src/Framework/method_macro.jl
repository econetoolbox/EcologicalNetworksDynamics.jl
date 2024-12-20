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
#   f(v::System{ValueType}, a, b) = f(v._value, a, b, v) # (generated)
#
# Two types of items can be listed in the 'depends' section:
#  - Component: means that the generated methods
#    will guard against use with system missing it.
#  - Another method: means that the generated methods
#    will guard against use with systems failing to meet requirements for this other method.

macro method(input...)
    method_macro(__module__, __source__, input...)
end
export @method

# Extract function to ease debugging with Revise.
function method_macro(__module__, __source__, input...)

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
    todep_infer(xp, ctx) = to_dependency(__module__, xp, ctx, :xerr)
    todep(xp, ctx) = to_dependency(__module__, xp, :ValueType, ctx, :xerr)

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
    # then the input expression must be a plain symbol or Path.To.symbol..
    # unless there is another programmatic way to add a method to a function in Julia?
    xp = input[1]
    (false) && (local fn_xp, ValueType_xp) # (reassure JuliaLS)
    @capture(xp, fn_xp_{ValueType_xp_} | fn_xp_)
    fn_xp isa Symbol ||
        fn_xp isa Expr && fn_xp.head == :. ||
        perr("Not a method identifier or path: $(repr(fn_xp)).")
    ValueType_xp =
        isnothing(ValueType_xp) ? :(nothing) :
        tovalue(ValueType_xp, "System value type", Type)
    push_res!(quote

        ValueType = $ValueType_xp # Explicit or inferred.
        fn = $(tovalue(fn_xp, "System method", Function))

    end)

    # Next come other optional specifications in any order.
    deps_xp = nothing # Evaluates to [components...]
    proptype = nothing
    prop_paths = []
    read_kw, write_kw = (:read_as, :write_as)
    prop_kw = nothing

    for i in input[2:end]

        # Dependencies section: specify the components required to use the method.
        list = nothing # (help JuliaLS)
        @capture(i, depends(list__))
        if !isnothing(list)
            isnothing(deps_xp) || perr("The `depends` section is specified twice.")
            deps_xp = :([])
            first = true
            for dep in list
                xp = if first
                    first = false
                    # Infer the value type from the first dep if possible.
                    quote
                        dep = $(todep_infer(dep, "First dependency"))
                        if isnothing(ValueType)
                            # Need to infer.
                            ValueType = if dep isa Function
                                vals = method_for_values(typeof(dep))
                                length(vals) == 1 || xerr(
                                    "First dependency: the function specified \
                                     has been recorded as a method for \
                                     [$(join(vals, ", "))]. \
                                     It is ambiguous which one the focal method \
                                     is being defined for.",
                                )
                                first(vals)
                            else
                                C = dep # Then it must be a component.
                                system_value_type(C)
                            end
                        else
                            if dep isa Function
                                specified_as_method(ValueType, typeof(dep)) ||
                                    xerr("Depends section: system value type \
                                          is supposed to be '$ValueType' \
                                          based on the first macro argument, \
                                          but '$dep' has not been recorded \
                                          as a system method for this type.")
                            else
                                C = dep
                                if !(C <: Component{ValueType})
                                    C_V = system_value_type(C)
                                    xerr("Depends section: system value type \
                                          is supposed to be '$ValueType' \
                                          based on the first macro argument, \
                                          but $C subtypes '$Component{$C_V}' \
                                          and not '$Component{$ValueType}'.")
                                end
                            end
                        end
                        dep
                    end
                else
                    todep(dep, "Depends section")
                end
                push!(deps_xp.args, xp)
            end
            continue
        end

        # Property section: specify whether the code can be accessed as a property.
        prop_kw, paths = nothing, nothing # (help JuliaLS)
        @capture(i, prop_kw_(paths__))
        if !isnothing(prop_kw)
            if Base.isidentifier(prop_kw)
                if !(prop_kw in (read_kw, write_kw))
                    perr("Invalid section keyword: $(repr(prop_kw)). \
                          Expected :$read_kw or :$write_kw or :depends.")
                end
                if !isnothing(proptype)
                    proptype == prop_kw && perr("The :$prop_kw section is specified twice.")
                    perr("Cannot specify both :$proptype section and :$prop_kw.")
                end
                for path in paths
                    is_identifier_path(path) || perr("Property name is not a simple \
                                                       identifier path: $(repr(path)).")
                end
                prop_paths = paths
                proptype = prop_kw
                continue
            end
        end

        perr("Unexpected @method section. \
              Expected `depends(..)`, `$read_kw(..)` or `$write_kw(..)`. \
              Got instead: $(repr(i)).")

    end

    if isnothing(deps_xp)
        deps_xp = :([])
    end

    if isempty(deps_xp.args)
        push_res!(
            quote
                isnothing(ValueType) && xerr("The system value type cannot be inferred \
                                              when no dependencies are given.\n\
                                              Consider making it explicit \
                                              with the first macro argument: \
                                              `$fn{MyValueType}`.")
            end,
        )
    end

    # Collect the dependencies now as it enables inferring the system value type.
    push_res!(quote
        raw_deps = $deps_xp
    end)

    # Split paths into (path, target, property_name)
    push_res!(quote
        prop_paths = map($[prop_paths...]) do path
            P = super(property_space_type(path, ValueType))
            last = last_in_path(path)
            (path, P, last)
        end
    end)

    # Scroll existing methods to find the ones to wrap
    # with methods receiving 'System' values as parameters.
    push_res!(
        quote
            # Collect information regarding every method to wrap: [(
            #   method: to be wrapped in a new checked method receiving `System`,
            #   types: list of positional parameters types,
            #   names: list of positional parameters names,
            #   receiver: the receiver parameter name,
            #   targets: receiver parameter types in the generated wrapper methods
            #            (either `System` or `PropertySpace`s,
            #             there may be several if invoker has specified
            #             several property paths)
            #   hook: the receiver parameter name,
            # )]
            to_wrap = []
            can_be_read_property = [false] # (wrap scalar to access from within the loop..
            can_be_write_property = [false] # .. without triggering global variable warnings)
            all_targets = OrderedSet() # Gather all possible target receivers.
            for mth in methods(fn)

                # Retrieve fixed-parameters types for the method.
                parms = collect(mth.sig.parameters[2:end])
                isempty(parms) && continue
                # Retrieve their names.
                # https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4?u=iago-lito
                names =
                    ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), mth.slot_syms)[2:end]

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
                    (what, set, type) ->
                        xerr("Receiving several (possibly different) $what \
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
                targets = $(
                    if isnothing(prop_kw)
                        quote
                            [System{ValueType}]
                        end
                    else
                        quote
                            maybe_propspaces = if n_parms_for_user == 1
                                can_be_read_property[1] = true
                            elseif n_parms_for_user == 2 && (
                                parms[1] <: ValueType ||
                                hook == first(names) && parms[2] <: ValueType
                            )
                                can_be_write_property[1] = true
                            else
                                false
                            end
                            if maybe_propspaces && !isempty(prop_paths)
                                # (avoid duplicate methods defs for properties aliases)
                                ps = OrderedSet(map(prop_paths) do (path, P, pname)
                                    P
                                end)
                                push!(ps, System{ValueType}) # (always have the system as a target)
                            else
                                [System{ValueType}]
                            end
                        end
                    end
                )
                for P in targets
                    push!(all_targets, P)
                end

                # Record for wrapping.
                push!(to_wrap, (mth, parms, names, receiver, targets, hook))
            end
            isempty(to_wrap) &&
                xerr("No suitable method has been found to mark $fn as a system method. \
                      Valid methods must have at least \
                      one 'receiver' argument of type ::$ValueType.")
        end,
    )

    push_res!(
        quote
            # Now that we have a guarantee that 'ValueType' has been completely inferred,
            # use it to guard against redundant method specifications.
            (specified_as_method(ValueType, typeof(fn)) && !REVISING) &&
                xerr("Function '$fn' already marked as a method \
                      for systems of '$ValueType'.")
        end,
    )

    # Check that consistent 'depends' component types have been specified.
    push_res!(quote
        # Expand method dependencies into the corresponding components.
        # Redundancy (including vertical ones)
        # are allowed in this context.
        deps = OrderedSet{CompType{ValueType}}()

        for rdep in raw_deps
            subdeps = if dep isa Function
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
    end)

    if prop_kw == read_kw
        push_res!(
            quote
                can_be_read_property[1] ||
                    xerr("The function cannot be called with exactly \
                          1 argument of type '$ValueType' \
                          as required to be set as a 'read' property.")
            end,
        )
    end

    if prop_kw == write_kw
        push_res!(
            quote
                can_be_write_property[1] ||
                    xerr("The function cannot be called with exactly 2 arguments, \
                          the first one being of type '$ValueType', \
                          as required to be set as a 'write' property.")
            end,
        )
    end

    # Check properties availability.
    push_res!(
        if prop_kw == read_kw
            quote
                for (path, P, pname) in prop_paths
                    has_read_property(P, Val(pname)) && xerr(
                        "The property $(repr(path)) is already defined for target '$P'.",
                    )
                end
            end
        else
            quote
                for (path, P, pname) in prop_paths
                    has_read_property(P, Val(pname)) ||
                        xerr("The property $(repr(path)) cannot be marked 'write' \
                              without having first been marked 'read' \
                              for target '$P'.")
                    has_write_property(P, Val(pname)) &&
                        xerr("The property $(repr(path)) is already marked 'write' \
                              for target '$P'.")
                end
            end
        end,
    )

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information should have been parsed and checked,
    # both at expansion time (within this very macro body code)
    # and generated code execution time
    # (within the code currently being generated although not executed yet).
    # The only remaining code to generate work is just the code required
    # for the system to work correctly.

    # Generate dependencies method.
    push_res!(quote
        for P in all_targets
            Framework.depends(::Type{P}, ::Type{typeof(fn)}) = deps
        end
    end)

    # Wrap the detected methods within checked methods receiving 'System' values.
    efn = LOCAL_MACROCALLS ? esc(fn_xp) : Meta.quot(cat_path(__module__, fn_xp))
    fn_path = Meta.quot(Meta.quot(fn_xp))
    push_res!(
        quote
            for (mth, parms, pnames, receiver, targets, hook) in to_wrap
                for P in targets
                    # Start from dummy (; kwargs...) signature/forward call..
                    # (hygienic temporary variables, generated for the target module)
                    local dep, a = Core.eval($__module__, :(gensym.([:dep, :a])))
                    xp = quote
                        function (::typeof($($efn)))(; kwargs...)
                            #    ^^^^^^^^^^-------^^
                            # (useful to get it working
                            #  when the macro is called within @testset blocks
                            #  with LOCAL_MACROCALLS = true:
                            #  https://stackoverflow.com/a/55292662/3719101)
                            $dep = first_missing_dependency_for($($efn), $receiver)
                            if !isnothing($dep)
                                $a = isabstracttype($dep) ? " a" : ""
                                throw(
                                    MethodError(
                                        $ValueType,
                                        $($fn_path),
                                        "Requires$($a) component $($dep).",
                                    ),
                                )
                            end
                            $($efn)(; kwargs...)
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
                                (:($name::$P), :(value($name)))
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
            end
        end,
    )

    # Property specification.
    # (for getproperty(s::System, ..))
    if !isnothing(proptype)
        set = (proptype == read_kw) ? :set_read_property! : :set_write_property!
        push_res!(quote
            for (_, P, pname) in prop_paths
                $set(P, pname, fn)
            end
        end)
    end

    # Record as specified to avoid it being recorded again.
    push_res!(
        quote
            Framework.specified_as_method(::Type{ValueType}, ::Type{typeof(fn)}) = true
            vals = method_for_values(typeof(fn))
            if isempty(vals)
                # Specialize for this freshly created value.
                Framework.method_for_values(::Type{typeof(fn)}) = vals
            end
            push!(vals, ValueType) # Append the new one in any case.
        end,
    )

    # Avoid confusing/leaky return type from macro invocation.
    push_res!(quote
        nothing
    end)

    res
end

# Check whether the function has already been specified as a @method
# for this system value type.
specified_as_method(::Type, ::Type{<:Function}) = false
# Reverse-map.
method_for_values(::Type{<:Function}) = DataType[]

# Check for either a component or an alternate method.
function to_dependency(mod, xp, V, ctx, xerr)
    qxp = Meta.quot(xp)
    quote
        dep = $(to_value(mod, xp, ctx, xerr, Any))
        if dep isa Function
            specified_as_method($V, typeof(dep)) || $xerr(
                "$($ctx): the function specified as a dependency \
                 has not been recorded as a system method for '$V':$(xpres($qxp, dep))",
            )
            dep
        else
            $(check_component_type_or_instance(xp, :dep, V, ctx, xerr))
        end
    end
end

# Version without an expected value type.
function to_dependency(mod, xp, ctx, xerr)
    qxp = Meta.quot(xp)
    quote
        dep = $(to_value(mod, xp, ctx, xerr, Any))
        if dep isa Function
            vals = method_for_values(typeof(dep))
            isempty(vals) &&
                $xerr("$($ctx): the function specified as a dependency has not \
                       been recorded as a system method:$(xpres($qxp, dep))")
            dep
        else
            $(check_component_type_or_instance(xp, :dep, ctx, xerr))
        end
    end
end

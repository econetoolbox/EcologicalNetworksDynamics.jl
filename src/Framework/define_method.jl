"""
Define a new system method and possible associated properties.

Caller defines the behaviour in a function containing at least one 'receiver':
an argument explicitly typed with the system wrapped value.

```jl
f(v::Value, ...) = <caller code>
```

Then, the call goes like:
```jl
define_method(
    f,
    (ValueType,); # If inference fails.
    depends=[component, component => reason, ..],
    read_as = [:name, :(prop.path), ..],
    # xor write_as = [:name, :(prop.path), ..],
)
```

This will generate additional methods to `f`
so it accepts `System{Value}` instead of `Value` as the receiver.
These wrapper methods check that components dependencies are met
before forwarding to the original method.

If an original method has the exact:
- `f(receiver)` signature, then it can be marked as a `read` property.
- `f(receiver, rhs)` signature, then it can be marked as a `write` property.

Sometimes, the method needs to take decision
depending on other system components that are not strict dependencies,
so the whole system needs to be queried and not just the wrapped value.
In this case, the invoker adds a 'hook' `::System` parameter to their signature:

```jl
f(v, a, b, _system::System) = ...
```

The generated wrapper method then elides this extra 'hook' argument,
but still forwards the whole system to it:

```jl
f(s::System{ValueType}, a, b) = f(value(s), a, b, s) # (generated)
```

Two types of items can be listed in the 'depends' section:
- Component: means that the generated methods
  will guard against use with system missing it.
- Another method: means that the generated methods
  will guard against use with systems failing to meet requirements for this other method.
"""

function define_method(
    fn::Function,
    V::Option{DataType} = nothing;
    depends = [],
    read_as = [],
    write_as = [],
)
    err(mess) = throw(ItemError(:method, fn, mess))

    #---------------------------------------------------------------------------------------
    # Input checks.

    V = V
    inferred = isnothing(V)

    deps = []
    for (i, dep) in enumerate(depends)
        dep = check_dependency(dep, "Method dependency [$i]", err)
        if isnothing(V)
            V = if dep isa Function
                vals = method_for_values(typeof(dep))
                length(vals) == 1 || err("First dependency: the function specified \
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
            based = inferred ? " based on the first macro argument" : ""
            if dep isa Function
                specified_as_method(V, typeof(dep)) ||
                    err("Depends section: system value type \
                         is supposed to be `$V`$based, \
                         but `$dep` has not been recorded \
                         as a system method for this type.")
            else
                C = dep
                if !(C <: Component{V})
                    C_V = system_value_type(C)
                    err("Depends section: system value type \
                         is supposed to be `$V`$based, \
                         but $C subtypes `$Component{$C_V}` \
                         and not `$Component{$V}`.")
                end
            end
        end
        push!(deps, dep)
    end

    isnothing(V) && err("The system value type cannot be inferred \
                         when no dependencies are given.\n\
                         Consider making it explicit \
                         with the first macro argument: \
                         `$fn{MyValueType}`.")

    !(isempty(read_as) || isempty(write_as)) &&
        err("Cannot specify both `read_as` and `write_as` sections.")

    proptype = isempty(write_as) ? (isempty(read_as) ? nothing : :read) : :write

    prop_paths = []
    for paths in (read_as, write_as)
        for (i, path) in enumerate(paths)
            is_identifier_path(path) || err("Property name [$i] is not a simple \
                                             identifier path$(valr(path))")
            push!(prop_paths, path)
        end
    end

    #---------------------------------------------------------------------------------------
    # All required information collected from input. Processing.

    # Split paths into (path, target, property_name)
    prop_paths = map(prop_paths) do path
        P = super(property_space_type(path, V))
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
    can_be_read_property = false
    can_be_write_property = false
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
            if p <: V
                push!(values, n)
            elseif p <: PropertySpace
                system_value_type(p) === V && push!(values, n)
            end
            p <: System{V} && push!(system_values, n)
            p === System && push!(systems_only, n)
        end
        severr =
            (what, set, type) -> err("Receiving several (possibly different) $what \
                                      is not yet supported by the framework. \
                                      Here both parameters :$(pop!(set)) and :$(pop!(set)) \
                                      are of type $type.")
        length(values) > 1 && severr("system/values parameters", values, V)
        isempty(values) && continue
        receiver = pop!(values)
        sv = system_values
        length(sv) > 1 && severr("system hooks", sv, System{V})
        hook = if isempty(system_values)
            so = systems_only
            length(so) > 1 && severr("system hooks", so, System)
            isempty(so) ? nothing : pop!(so)
        else
            pop!(system_values)
        end

        n_parms_for_user = length(parms) - !isnothing(hook)
        if !isnothing(proptype)
            if n_parms_for_user == 1
                can_be_read_property = true
            elseif n_parms_for_user == 2 &&
                   (parms[1] <: V || hook == first(names) && parms[2] <: V)
                can_be_write_property = true
            end
        end

        # Record for wrapping.
        push!(to_wrap, (mth, parms, names, receiver, hook))
    end
    isempty(to_wrap) &&
        err("No suitable method has been found to mark $fn as a system method. \
             Valid methods must have at least \
             one 'receiver' argument of type ::$V.")

    # Use 'ValueType' to guard against redundant method specifications.
    (specified_as_method(V, typeof(fn)) && !REVISING) &&
        err("Function `$fn` already marked as a method for systems of `$V`.")

    # Check that consistent 'depends' component types have been specified.
    # Expand method dependencies into the corresponding components.
    # Redundancy (including vertical ones)
    # are allowed in this context.
    raw_deps = deps
    deps = OrderedSet{CompType{V}}()
    for rdep in raw_deps
        subdeps = if rdep isa Function
            F.depends(System{V}, typeof(rdep))
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

    if proptype == :read
        can_be_read_property || err("The function cannot be called with exactly \
                                        1 argument of type `$V` \
                                        as required to be set as a 'read' property.")
    end

    if proptype == :write
        can_be_write_property ||
            err("The function cannot be called with exactly 2 arguments, \
                 the first one being of type `$V`, \
                 as required to be set as a 'write' property.")
    end

    # Check properties availability.
    if proptype == :read
        for (path, P, pname) in prop_paths
            has_read_property(P, Val(pname)) &&
                err("The property $(repr(path)) is already defined for target `$P`.")
        end
    else
        for (path, P, pname) in prop_paths
            has_read_property(P, Val(pname)) ||
                err("The property $(repr(path)) cannot be marked 'write' \
                     without having first been marked 'read' \
                     for target `$P`.")
            has_write_property(P, Val(pname)) &&
                err("The property $(repr(path)) is already marked 'write' \
                     for target `$P`.")
        end
    end

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information
    # should have been parsed, evaluated and checked.
    # The only remaining code to generate and evaluate
    # is the code required for the system to work correctly.

    # Generate dependencies method.
    Fn = Type{typeof(fn)}
    Target = System{V}
    eval(quote
        F.depends(::Type{$Target}, ::$Fn) = $deps
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
                    throw(MethodCallError($V, nameof($fn), "Requires$($a) component $($dep)."))
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
        set = (proptype == :read) ? set_read_property! : set_write_property!
        for (_, P, pname) in prop_paths
            set(P, pname, fn)
        end
    end

    # Record as specified to avoid it being recorded again.
    eval(quote
        $F.specified_as_method(::Type{$V}, ::$Fn) = true
    end)
    vals = method_for_values(typeof(fn))
    if isempty(vals)
        # Specialize for this freshly created value.
        eval(quote
            $F.method_for_values(::$Fn) = $vals
        end)
    end
    push!(vals, V) # Append the new one in any case.

end
export define_method

# Check whether the function has already been specified as a @method
# for this system value type.
specified_as_method(::Type, ::Type{<:Function}) = false
# Reverse-map.
method_for_values(::Type{<:Function}) = DataType[]

# Check for either a component or an alternate method.
function check_dependency(dep, V, ctx, err)
    if dep isa Function
        specified_as_method(V, typeof(dep)) ||
            err("$ctx:\nThe function specified as a dependency \
                 has not been recorded as a system method for `$V`$(valr(dep))")
        dep
    else
        check_component(dep, V, ctx, err)
    end
end

# Version without an expected value type.
function check_dependency(dep, ctx, err)
    if dep isa Function
        vals = method_for_values(typeof(dep))
        isempty(vals) && err("$ctx:\nThe function specified as a dependency has not \
                              been recorded as a system method$(valr(dep))")
        dep
    else
        check_component(dep, ctx, err)
    end
end

# Call later to append aliases.
# TODO: this is only tested by the above client package yet. Test within framework tests.
macro alias(new, old, V)
    new, old = Meta.quot.((new, old))
    quote
        $alias_property!($new, $old, $V)
    end
end
export @alias
function alias_property!(a, b, V)
    # Extract original.
    (A, B) = property_space_type.((a, b), (V,))
    (Pa, Pb) = super.((A, B))
    (na, nb) = last_in_path.((a, b))
    fn_b = read_property(Pb, Val(nb)) # Checked.
    fn_b! = possible_write_property(Pb, Val(nb))
    set_property!(Pa, na, fn_b, fn_b!)
end

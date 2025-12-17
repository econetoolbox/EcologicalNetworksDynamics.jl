# Convenience macro for defining a new component.
#
# Invoker defines possible abstract component supertype,
# and/or some blueprints types providing only the created component,
# then invokes:
#
#   @component Name{ValueType} requires(components...) blueprints(name::Type, ...)
#
# Or:
#
#   @component Name <: SuperComponentType requires(components...) blueprints(name::Type, ...)
#
# This alternate block-form is supported:
#
#   @component begin
#       Name{ValueType}
#  (or) Name <: SuperComponentType
#       requires(components...)
#       blueprints(name::Type, ModuleName, ...) # (all @blueprints exported from module)
#   end
#
# After all input checks pass, the following (approximate) component code
# should result from expansion:
#
# ------------------------------------------------------------------
#   # Component type.
#   struct _Name <: SuperComponentType (or Component{ValueType})
#     Blueprint1::Type{Blueprint{ValueType}}
#     Blueprint2::Type{Blueprint{ValueType}}
#     ...
#   end
#
#   # Component singleton value.
#   const Name = _Name(
#       BlueprintType1,
#       BlueprintType2,
#       ...
#   )
#   singleton_instance(::Type{_Name}) = Name
#
#   # Base blueprints.
#   componentsof(::Blueprint1) = (_Name,)
#   componentsof(::Blueprint2) = (_Name,)
#   ...
#
#   requires(::Type{_Name}) = ...
# ------------------------------------------------------------------
#
macro component(input...)
    mod = __module__
    src, input = Meta.quot.((__source__, input))
    quote
        $component_macro($mod, $src, $input)
        nothing
    end
end
export @component

function component_macro(mod, src, input)

    # Raise on failure.
    item_err(mess, item) = throw(ItemMacroError(:component, item, src, mess))
    component_name = Ref{Option{Symbol}}(nothing) # Refined later.
    err(mess) = item_err(mess, component_name[])

    # Convenience local wrap.
    ceval(xp, ctx, type) = checked_eval(mod, xp, ctx, err, type)

    #---------------------------------------------------------------------------------------
    # Parse and check macro input.

    # Unwrap input if given in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    li = length(input)
    if li == 0 || li > 3
        err("$(li == 0 ? "Not enough" : "Too much") macro input provided. Example usage:\n\
             | @component begin\n\
             |      Name <: SuperComponent\n\
             |      requires(...)\n\
             |      blueprints(...)\n\
             | end\n")
    end

    # Extract component name, value type and supercomponent from the first section.
    component = input[1]
    (false) && (local name, value_type, super) # (reassure JuliaLS)
    @capture(component, name_{value_type_} | (name_ <: super_))
    isnothing(name) &&
        err("Expected component `Name{ValueType}` or `Name <: SuperComponent`, \
             got instead: $(repr(component)).")
    component_name[] = name
    if !isnothing(super)
        SuperComponent = ceval(super, "Evaluating given supercomponent", DataType)
        if !(SuperComponent <: Component)
            err("Supercomponent: $SuperComponent does not subtype $Component.")
        end
        ValueType = system_value_type(SuperComponent)
    elseif !isnothing(value_type)
        ValueType = ceval(value_type, "Evaluating given system value type", DataType)
        SuperComponent = Component{ValueType}
    end
    isdefined(mod, name) && err("Cannot define component '$name': name already defined.")
    # Convenience local wrap.
    evalbp(xp, ctx) = eval_blueprint_type(mod, xp, ValueType, ctx, err)
    evalcomp(xp, ctx) = eval_component(mod, xp, ValueType, ctx, err)

    # Next come other optional sections in any order.
    requires = nothing # [(component => reason), ...]
    blueprints = nothing # [(identifier, path), ...]

    for i in input[2:end]

        # Require section: specify necessary components.
        (false) && (local reqs) # (reassure JuliaLS)
        @capture(i, requires(reqs__))
        if !isnothing(reqs)
            isnothing(requires) || err("The `requires` section is specified twice.")
            requires = eval_comp_reasons(mod, reqs, ValueType, "Required component", err)
            continue
        end

        # Blueprints section: specify blueprints providing the new component.
        (false) && (local bps) # (reassure JuliaLS)
        @capture(i, blueprints(bps__))
        if !isnothing(bps)
            isnothing(blueprints) || err("The `blueprints` section is specified twice.")
            blueprints = []
            for bp in bps
                (false) && (local bpname, bptype) # (reassure JuliaLS)
                @capture(bp, bpname_::bptype_)
                if isnothing(bpname)
                    modname = bp
                    push!(blueprints, ceval(modname, "Blueprints list", Module))
                else
                    B = evalbp(bptype, "Blueprint")
                    push!(blueprints, (bpname, B))
                end
            end
            continue
        end

        err("Invalid @component section. \
              Expected `requires(..)` or `blueprints(..)`, \
              got instead: $(repr(i)).")

    end
    isnothing(requires) && (requires = [])
    isnothing(blueprints) && (blueprints = [])

    # Check that consistent required component types have been specified.
    reqs = triangular_vertical_guard(requires, ValueType, err)

    # Guard against redundancies / collisions among base blueprints.
    base_blueprints = []
    for spec in blueprints
        # [(blueprint name as component field, blueprint type)]
        blueprints = if spec isa Module
            # Collect all blueprints within the given module
            # and use their type names as component fields names.
            bps = []
            # /!\ Use unexposed Julia API here: unsorted_names,
            # so that the order of base blueprints within the components
            # match their order of definition within the lib.
            # If this ever becomes unavailable, just switch back to `names`.
            for name in Base.unsorted_names(spec)
                local B = getfield(spec, name)
                B isa DataType && B <: Blueprint{ValueType} || continue
                push!(bps, (name, B))
            end
            isempty(bps) && err("Module '$spec' exports no blueprint for '$ValueType'.")
            bps
        else
            [spec] # Only one (name, B) pair has been explicitly provided.
        end
        for (name, B) in blueprints
            # Triangular-check.
            for (other, Other) in base_blueprints
                other == name && err("Base blueprint $(repr(other)) \
                                      both refers to '$Other' and to '$B'.")
                Other == B && err("Base blueprint '$B' bound to \
                                   both names $(repr(other)) and $(repr(name)).")
            end
            push!(base_blueprints, (name, B))
        end
    end

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information
    # should have been parsed, evaluated and checked.
    # The only remaining code to generate and evaluate
    # is the code required for the system to work correctly.

    # Construct the component type, with base blueprints types as fields.
    cname = component_name[]
    ctype = Symbol(:_, cname)
    str = quote
        struct $ctype <: $SuperComponent end
        $ctype
    end
    fields = str.args[2].args[3].args
    for (name, B) in base_blueprints
        push!(fields, quote
            $name::Type{$B}
        end)
    end
    CompType = mod.eval(str)

    # Construct the singleton instance.
    cstr = :($ctype())
    for (_, B) in base_blueprints
        push!(cstr.args, B)
    end
    cstr = quote
        const $cname = $cstr
        $cname
    end
    CompInstance = mod.eval(cstr)
    TC = Type{CompType} # (or would trigger 'local variable cannot be used in closure decl')
    # Connect instance to type.
    eval(quote
        Framework.singleton_instance(::$TC) = $CompInstance
    end)

    # Ensure singleton unicity.
    eval(
        quote
            (C::$TC)(args...; kwargs...) = throw("Cannot construct other instances of $C.")
        end,
    )

    # Connect to blueprint types.
    for (_, B) in base_blueprints
        eval(quote
            Framework.componentsof(::$B) = ($CompType,)
        end)
    end

    # Setup the components required.
    iter() = CompsReasons{ValueType}(k => v for (k, v) in reqs) # Copy to avoid leaks.
    eval(quote
        Framework.requires(::$TC) = $iter()
    end)
end

# For specification by framework users.
shortline(io, B::Type{<:Blueprint}) = @invoke show(io, B::DataType)

# Helpful display resuming base blueprint types for this component,
# assuming it has been generated by the above.
function Base.show(io::IO, ::MIME"text/plain", c::Component)
    it = crayon"italics"
    V = system_value_type(c)
    print(io, "$component_color$c$reset $grayed(component for $V")
    names = fieldnames(typeof(c))
    if isempty(names)
        print(io, " with no base blueprint")
    else
        println(io, ", expandable from:")
        for name in names
            B = getfield(c, name)
            print(io, "  $blueprint_color$name$reset$grayed: $it")
            shortline(io, B)
            println(io, "$reset$grayed,")
        end
    end
    print(io, ")$reset")
end

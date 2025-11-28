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
# Consistency checks are run by the macro then by the generated code.
# When all check pass, the following (approximate) component code
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
    # Extract function to ease debugging with Revise.
    component_macro(__module__, __source__, input...)
end
export @component

function component_macro(__module__, __source__, input...)

    # Push resulting generated code to this variable.
    res = quote end
    push_res!(xp) = xp.head == :block ? append!(res.args, xp.args) : push!(res.args, xp)

    # Raise *during expansion* if parsing fails.
    perr(mess) = throw(ItemMacroParseError(:component, __source__, mess))

    # Raise *during execution* if the macro was invoked with inconsistent input.
    # (assuming the `NewComponent` generated variable has been set)
    src = Meta.quot(__source__)
    push_res!(
        quote
            NewComponent = nothing # Refined later.
            xerr =
                (mess) -> throw(ItemMacroExecError(:component, NewComponent, $src, mess))
        end,
    )

    # Convenience local wrap.
    tovalue(xp, ctx, type) = to_value(__module__, xp, ctx, :xerr, type)
    tobptype(xp, ctx) = to_blueprint_type(__module__, xp, :ValueType, ctx, :xerr)
    tocomp(xp, ctx) = to_component(__module__, xp, :ValueType, ctx, :xerr)

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
             | @component begin\n\
             |      Name <: SuperComponent\n\
             |      requires(...)\n\
             |      blueprints(...)\n\
             | end\n",
        )
    end

    # Extract component name, value type and supercomponent from the first section.
    component_xp = input[1]
    (false) && (local name, value_type, super) # (reassure JuliaLS)
    @capture(component_xp, name_{value_type_} | (name_ <: super_))
    isnothing(name) &&
        perr("Expected component `Name{ValueType}` or `Name <: SuperComponent`, \
              got instead: $(repr(component_xp)).")
    if !isnothing(super)
        # Infer value type from the abstract supercomponent.
        # Same, for abstract component types.
        is_identifier_path(super) ||
            perr("Expected supercomponent path, got: $(repr(super)).")
        push_res!(
            quote
                SuperComponent =
                    $(tovalue(super, "Evaluating given supercomponent", DataType))
                if !(SuperComponent <: Component)
                    xerr("Supercomponent: $SuperComponent does not subtype $Component.")
                end
                ValueType = system_value_type(SuperComponent)
            end,
        )
    elseif !isnothing(value_type)
        push_res!(
            quote
                ValueType =
                    $(tovalue(value_type, "Evaluating given system value type", DataType))
                SuperComponent = Component{ValueType}
            end,
        )
    end
    component_name = name
    component_sym = Meta.quot(name)
    component_type = Symbol(:_, name)
    push_res!(
        quote
            isdefined($__module__, $component_sym) &&
                xerr("Cannot define component '$($component_sym)': name already defined.")
            NewComponent = $component_sym
        end,
    )

    # Next come other optional sections in any order.
    requires_xp = nothing # Evaluates to [(component => reason), ...]
    blueprints_xp = nothing # Evaluates to [(identifier, path), ...]

    for i in input[2:end]

        # Require section: specify necessary components.
        (false) && (local reqs) # (reassure JuliaLS)
        @capture(i, requires(reqs__))
        if !isnothing(reqs)
            isnothing(requires_xp) || perr("The `requires` section is specified twice.")
            requires_xp =
                to_comp_reasons(__module__, reqs, :ValueType, "Required component", :xerr)
            continue
        end

        # Blueprints section: specify blueprints providing the new component.
        (false) && (local bps) # (reassure JuliaLS)
        @capture(i, blueprints(bps__))
        if !isnothing(bps)
            isnothing(blueprints_xp) || perr("The `blueprints` section is specified twice.")
            blueprints_xp = :([])
            for bp in bps
                (false) && (local bpname, B, modname) # (reassure JuliaLS)
                @capture(bp, bpname_::B_)
                if isnothing(bpname)
                    is_identifier_path(bp) ||
                        perr("Expected `name::Type` or `ModuleName` to specify blueprint, \
                              found instead: $(repr(bp)).")
                    push!(blueprints_xp.args, tovalue(bp, "Blueprints list", Module))
                else
                    xp = tobptype(B, "Blueprint")
                    push!(blueprints_xp.args, :($(Meta.quot(bpname)), $xp))
                end
            end
            continue
        end

        perr("Invalid @component section. \
              Expected `requires(..)` or `blueprints(..)`, \
              got instead: $(repr(i)).")

    end
    isnothing(requires_xp) && (requires_xp = :([]))
    isnothing(blueprints_xp) && (blueprints_xp = :([]))

    # Check that consistent required component types have been specified.
    push_res!(quote
        # Required components.
        reqs = $requires_xp
        reqs = triangular_vertical_guard(reqs, ValueType, xerr)
    end)

    # Guard against redundancies / collisions among base blueprints.
    push_res!(
        quote
            base_blueprints = []
            for spec in $blueprints_xp
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
                    isempty(bps) && xerr("Module '$spec' \
                                          exports no blueprint for '$ValueType'.")
                    bps
                else
                    # Only one pair has been explicitly provided.
                    local name, B = spec
                    [(name, B)]
                end
                for (name, B) in blueprints
                    # Triangular-check.
                    for (other, Other) in base_blueprints
                        other == name && xerr("Base blueprint $(repr(other)) \
                                               both refers to '$Other' and to '$B'.")
                        Other == B && xerr("Base blueprint '$B' bound to \
                                            both names $(repr(other)) and $(repr(name)).")
                    end
                    push!(base_blueprints, (name, B))
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

    # Construct the component type, with base blueprints types as fields.
    ena = esc(component_name)
    ety = esc(component_type)
    enas = Meta.quot(component_name)
    etys = Meta.quot(component_type)
    push_res!(quote
        str = quote
            struct $($etys) <: $SuperComponent end
        end
        for (name, B) in base_blueprints
            push!(str.args[2].args[3].args, quote
                $name::Type{$B}
            end)
        end
        $__module__.eval(str)
        CompType = invokelatest(() -> $ety)
    end)

    # Construct the singleton instance.
    push_res!(
        quote
            cstr = :($($etys)())
            for (_, B) in base_blueprints
                push!(cstr.args, B)
            end
            cstr = quote
                const $($enas) = $cstr
            end
            $__module__.eval(cstr)
            # Connect instance to type.
            Framework.singleton_instance(::Type{CompType}) = $ena
            # Ensure singleton unicity.
            (C::Type{CompType})(args...; kwargs...) =
                throw("Cannot construct other instances of $C.")
        end,
    )

    # Connect to blueprint types.
    push_res!(quote
        for (_, B) in base_blueprints
            $__module__.eval(quote
                $Framework.componentsof(::$B) = $($ety,)
            end)
        end
    end)

    # Setup the components required.
    push_res!(
        quote
            Framework.requires(::Type{$ety}) =
                CompsReasons{ValueType}(k => v for (k, v) in reqs) # Copy to avoid leaks.
        end,
    )

    # Helpful display resuming base blueprint types for this component.
    push_res!(
        quote
            function Base.show(io::IO, ::MIME"text/plain", C::$ety)
                it = crayon"italics"
                print(io, "$component_color$C$reset $grayed(component for $ValueType")
                names = fieldnames(typeof(C))
                if isempty(names)
                    print(io, " with no base blueprint")
                else
                    println(io, ", expandable from:")
                    for name in fieldnames(typeof(C))
                        B = getfield(C, name)
                        print(io, "  $blueprint_color$name$reset$grayed: $it")
                        shortline(io, B)
                        println(io, "$reset$grayed,")
                    end
                end
                print(io, ")$reset")
            end
        end,
    )

    # Avoid confusing/leaky return type from macro invocation.
    push_res!(quote
        nothing
    end)

    res
end

# For specification by framework users.
shortline(io, B::Type{<:Blueprint}) = @invoke show(io, B::DataType)

# Convenience macro for defining a new blueprint.
#
# Invoker defines the blueprint struct
# (before the corresponding components are actually defined),
# and associated late_check/expand!/etc. methods the way they wish,
# and then calls:
#
#   @blueprint Name "short string answering 'expandable from'" depends(components...)
#
# to record their type as a blueprint.
#
# Regarding the blueprints 'brought': make an ergonomic BET.
# Any blueprint field typed with `BroughtField`
# is automatically considered 'potential brought':
# the macro invocation makes it work out of the box.
# The following methods are relevant then:
#
#   # Generated:
#   brought(::Blueprint) = iterator over the brought fields, skipping 'nothing' values.
#
#   # Invoker-defined:
#   implied_blueprint_for(::Blueprint, ::Type{CompType}) = ...
#   <XOR> implied_blueprint_for(::Blueprint, ::CompType) = ... # (for convenience)
#
# And for blueprint user convenience, the generated code also overrides:
#
#   setproperty!(::Blueprint, field, value)
#
# with something comfortable:
#   - When given `nothing` as a value, void the field.
#   - When given a blueprint, check its provided components for consistency then *embed*.
#   - When given a comptype or a singleton component instance, make it *implied*.
#   - When given anything else, query the following for a callable blueprint constructor:
#
#       constructor_for_embedded(::Blueprint, ::Val{fieldname}) = Component
#       # (defaults to the provided component if single, not reified/overrideable yet)
#
#     then pass whatever value to this constructor to get this sugar:
#
#       blueprint.field = value  --->  blueprint.field = EmbeddedBlueprintConstructor(value)
#
# ERGONOMIC BET: This will only work if there is no ambiguity which constructor to call:
# make it only work if the component singleton instance brought by the field is callable,
# as this means there is an unambiguous default blueprint to be constructed.

# Dedicated field type to be automatically detected as brought blueprints.
struct BroughtField{C,V} # where C<:CompType{V} (enforce)
    value::Union{Nothing,Blueprint{V},Type{<:C}}
end
Brought(C::CompType{V}) where {V} = BroughtField{C,V}
Brought(c::Component) = Brought(typeof(c))
componentof(::Type{BroughtField{C,V}}) where {C,V} = C
# Basic query.
does_bring(bp::BroughtField) = !isnothing(refvalue(bp))
does_imply(bp::BroughtField) = does_bring(bp) && refvalue(bp) isa Type
does_embed(bp::BroughtField) = does_bring(bp) && refvalue(bp) isa Blueprint
export Brought, does_bring, does_imply, does_embed
embedded(bp::BroughtField) = does_embed(bp) ? refvalue(bp) : nothing
implied(bp::BroughtField) = does_imply(bp) ? refvalue(bp) : nothing
export embedded, implied

# The code checking macro invocation consistency requires
# that pre-requisites (methods implementations) be specified *prior* to invocation.
macro blueprint(input...)
    mod = __module__
    src, input = Meta.quot.((__source__, input))
    quote
        $blueprint_macro($mod, $src, $input)
        nothing
    end
end
export @blueprint

function blueprint_macro(mod, src, input)

    # Raise on failure.
    item_err(mess, item) = throw(ItemMacroError(:blueprint, item, src, mess))
    new_blueprint = Ref{Option{DataType}}(nothing) # Refine later.
    err(mess) = item_err(mess, new_blueprint[])

    mod, input = parse_module(mod, input...)

    # Convenience local wrap.
    ceval(xp, ctx, type) = checked_eval(mod, xp, ctx, err, type)

    #---------------------------------------------------------------------------------------
    # Parse and check macro input.
    # It has become very simple now,
    # although it used to be more complicated with several unordered sections to parse.
    # Keep it flexible for now in case it becomes complicated again.

    # Unwrap input if given in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    li = length(input)
    if li == 0 || li > 3
        err("$(li == 0 ? "Not enough" : "Too much") macro input provided. Example usage:\n\
             | @blueprint Name \"short description\" depends(Components...)\n")
    end

    # The first section needs to be a concrete blueprint type.
    # Use it to extract the associated underlying expected system value type,
    # checked for consistency against upcoming other (implicitly) specified blueprints.
    xp = input[1]
    new_blueprint[] = ceval(xp, "Blueprint type", DataType)
    NewBlueprint = new_blueprint[]
    NewBlueprint <: Blueprint || err("Not a subtype of '$Blueprint': '$NewBlueprint'.")
    isabstracttype(NewBlueprint) &&
        err("Cannot define blueprint from an abstract type: '$NewBlueprint'.")
    ValueType = system_value_type(NewBlueprint)
    specified_as_blueprint(NewBlueprint) && err("Type '$NewBlueprint' already marked \
                                                 as a blueprint for systems of '$ValueType'.")
    serr(mess) = syserr(ValueType, mess)

    # Extract possible short description line.
    # TODO: test.
    shortline = if length(input) > 1
        xp = input[2]
        ceval(xp, "Blueprint short description", String)
    else
        nothing
    end

    # Extract possible required components.
    deps = if length(input) > 2
        depends = input[3]
        (false) && (local comps) # (reassure JuliaLS)
        @capture(depends, depends(comps__))
        isnothing(comps) && (comps = [])
        eval_comp_reasons(mod, comps, ValueType, "Required component", err)
    else
        []
    end

    # No more sophisticated sections then.
    # Should they be needed once again, inspire from @component macro to restore them.
    #---------------------------------------------------------------------------------------

    # Check that consistent brought blueprints types have been specified.
    # Brought blueprints/components
    # are automatically inferred from the struct fields.
    broughts = OrderedDict{Symbol,CompType{ValueType}}()
    convenience_methods = Bool[]
    abstract_implied = Bool[]
    for (name, fieldtype) in zip(fieldnames(NewBlueprint), NewBlueprint.types)

        fieldtype <: BroughtField || continue
        C = componentof(fieldtype)
        # Check whether either the specialized method XOR its convenience alias
        # have been defined.
        sp = hasmethod(implied_blueprint_for, Tuple{NewBlueprint,Type{C}})
        conv = hasmethod(implied_blueprint_for, Tuple{NewBlueprint,C})
        (conv || sp) || err("Method $implied_blueprint_for($NewBlueprint, $C) unspecified \
                             to implicitly bring $C from $NewBlueprint blueprints.")
        (conv && sp) && err("Ambiguity: the two following methods have been defined:\n  \
                             $implied_blueprint_for(::$NewBlueprint, ::$C)\n  \
                             $implied_blueprint_for(::$NewBlueprint, ::$Type{$C})\n\
                             Consider removing either one.")

        # The above does *not* check that the method
        # has been specialized for every possible component type subtyping C.
        # This will need to be checked at runtime,
        # but raise this flag if C is abstract
        # to define a neat error fallback in case it's not.
        abs = isabstracttype(C)

        # Triangular-check against redundancies.
        for (a, Already) in broughts
            vertical_guard(
                C,
                Already,
                () -> err("Both fields '$a' and '$name' potentially bring $C."),
                (Sub, Sup) -> err("Fields '$name' and '$a': \
                                   brought blueprint $Sub is also specified as $Sup."),
            )
        end

        broughts[name] = C
        push!(convenience_methods, conv)
        push!(abstract_implied, abs)
    end

    #---------------------------------------------------------------------------------------
    # Guard against dependency redundancies.
    checked_deps = triangular_vertical_guard(deps, ValueType, err)

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information
    # should have been parsed, evaluated and checked.
    # The only remaining code to generate and evaluate
    # is the code required for the system to work correctly.

    for (C, conv, abs) in zip(values(broughts), convenience_methods, abstract_implied)
        # In case the convenience `implied_blueprint_for` has been defined,
        # forward the proper calls to it.
        if conv
            eval(
                quote
                    Framework.implied_blueprint_for(b::$NewBlueprint, C::Type{$C}) =
                        implied_blueprint_for(b, singleton_instance(C))
                end,
            )
        end
        # In case the brought component type is abstract,
        # define a fallback method in case the components lib
        # provided no way of implying a particular subtype of it.
        # TODO: find a way to raise this error earlier
        # during field assignment or construction.
        if abs
            eval(
                quote
                    function Framework.implied_blueprint_for(
                        b::$NewBlueprint,
                        Sub::Type{<:$C},
                    )
                        err() =
                            UnimplementedImpliedMethod{$ValueType}($NewBlueprint, $C, Sub)
                        isabstracttype(Sub) && throw(err())
                        try
                            # The convenience method may have been implemented instead.
                            implied_blueprint_for(b, singleton_instance(Sub))
                        catch e
                            e isa Base.MethodError && rethrow(err())
                            rethrow(e)
                        end
                    end
                end,
            )
        end
    end

    # Setup expansion dependencies.
    eval(
        quote
            Framework.expands_from(::$NewBlueprint) = $checked_deps

            # Setup the blueprints brought.
            Framework.brought(b::$NewBlueprint) =
                I.map(
                    I.filter(
                        !isnothing,
                        I.map(f -> refvalue(getfield(b, f)), keys($broughts)),
                    ),
                ) do f
                    f isa Component ? typeof(f) : f
                end

            # Protect/enhance field assignement for brought blueprints.
            function Base.setproperty!(b::$NewBlueprint, prop::Symbol, rhs)
                prop in keys($broughts) || return setfield!(b, prop, rhs)
                C = $broughts[prop]
                # Defer all checking to conversion methods.
                bf = try
                    Base.convert(BroughtField{C,$ValueType}, rhs)
                catch e
                    e isa BroughtConvertFailure && # Additional context available.
                        rethrow(BroughtAssignFailure($NewBlueprint, prop, e))
                    rethrow(e)
                end
                setfield!(b, prop, bf)
            end

            # Enhance display, special-casing brought fields.
            Base.show(io::IO, b::$NewBlueprint) = display_short(io, b)
            Base.show(io::IO, ::MIME"text/plain", b::$NewBlueprint) =
                display_long(io, b, 0)

            function Framework.display_short(io::IO, bp::$NewBlueprint)
                comps = provided_comps_display(bp, 0, false)
                print(io, "$comps:$(nameof($NewBlueprint))(")
                for (i, name) in enumerate(fieldnames($NewBlueprint))
                    i > 1 && print(io, ", ")
                    print(io, "$name: ")
                    # Dispatch on both (bp, name) and field value to allow
                    # either kind of specialization.
                    value = getfield(bp, name)
                    display_blueprint_field_short(io, value, bp, Val(name))
                end
                print(io, ")")
            end

            function Framework.display_long(io::IO, bp::$NewBlueprint, level)
                comps = provided_comps_display(bp, level, true)
                g = level == 0 ? "" : grayed
                print(
                    io,
                    "$(g)blueprint for$reset $comps: \
                     $blueprint_color$(nameof($NewBlueprint))$reset {",
                )
                preindent = repeat("  ", level)
                level += 1
                indent = repeat("  ", level)
                names = fieldnames($NewBlueprint)
                for name in names
                    print(io, "\n$indent$field_color$name:$reset ")
                    value = getfield(bp, name)
                    display_blueprint_field_long(io, value, bp, Val(name), level)
                    print(io, ",")
                end
                if !isempty(names)
                    print(io, "\n$preindent")
                end
                print(io, "}")
            end
        end,
    )

    # Record to avoid multiple calls to `@blueprint A`.
    if !isnothing(shortline)
        eval(quote
            Framework.shortline(io, ::Type{$NewBlueprint}) = print(io, $shortline)
        end)
    end
    eval(quote
        Framework.specified_as_blueprint(::Type{$NewBlueprint}) = true
    end)

end

#-------------------------------------------------------------------------------------------
# Minor stubs for the macro to work.

specified_as_blueprint(B::Type{<:Blueprint}) = false

# Stubs for display methods.
function display_short end
function display_long end

# ==========================================================================================
# Protect against constructing invalid brought fields.
# These checks are either run when doing `host.field = ..` or `Host(..)`.

# From nothing to not bring anything.
Base.convert(::Type{BroughtField{C,V}}, ::Nothing) where {C,V} = BroughtField{C,V}(nothing)

#-------------------------------------------------------------------------------------------
# From a component type to imply it.

function Base.convert(
    ::Type{BroughtField{eC,eV}}, # ('expected C', 'expected V')
    aC::CompType{aV}; # ('actual C', 'actual V')
    input = aC,
) where {eV,eC,aV}
    err(m) = throw(BroughtConvertFailure(eC, m, input))
    aV === eV || err("The input would not imply a component for '$eV', but for '$aV'.")
    aC <: eC || err("The input would instead imply $aC.")
    # TODO: How to check whether `implied_blueprint_for` has been defined for aC here?
    # Context is missing because 'NewBlueprintType' is unknown.
    BroughtField{eC,eV}(aC)
end

# From a component value for convenience.
Base.convert(::Type{BroughtField{C,V}}, c::Component) where {V,C} =
    Base.convert(BroughtField{C,V}, typeof(c); input = c)

#-------------------------------------------------------------------------------------------
# From a blueprint to embed it.

function Base.convert(::Type{BroughtField{eC,eV}}, bp::Blueprint{aV}) where {eC,eV,aV}
    err(m) = throw(BroughtConvertFailure(eC, m, bp))
    aV === eV || err("The input does not embed a blueprint for '$eV', but for '$aV'.")
    comps = componentsof(bp)
    length(comps) == 1 || err("Blueprint would instead expand into [$(join(comps, ", "))].")
    aC = first(comps)
    aC <: eC || err("Blueprint would instead expand into $aC.")
    BroughtField{eC,eV}(bp)
end

#-------------------------------------------------------------------------------------------
# From arguments to embed with a call to implicit constructor.

function Base.convert(BF::Type{BroughtField{C,V}}, input::Any) where {C,V}
    BF(implicit_constructor_for(C, V, (input,), (;), input))
end

function Base.convert(BF::Type{BroughtField{C,V}}, args::Tuple) where {C,V}
    BF(implicit_constructor_for(C, V, args, (;), args))
end

function Base.convert(BF::Type{BroughtField{C,V}}, kwargs::NamedTuple) where {C,V}
    BF(implicit_constructor_for(C, V, (), kwargs, kwargs))
end

function Base.convert(BF::Type{BroughtField{C,V}}, akw::Tuple{Tuple,NamedTuple}) where {C,V}
    args, kwargs = akw
    BF(implicit_constructor_for(C, V, args, kwargs, akw))
end

#-------------------------------------------------------------------------------------------
# Transparent use of the broughtfield inner value.

refvalue(bf::BroughtField) = getfield(bf, :value)
Base.getproperty(bf::BroughtField, name::Symbol) = getproperty(refvalue(bf), name)
Base.setproperty!(bf::BroughtField, name::Symbol, rhs) =
    setproperty!(refvalue(bf), name, rhs)

Base.:(==)(a::BroughtField, b) = refvalue(a) == b
Base.:(==)(a, b::BroughtField) = a == refvalue(b)
Base.:(==)(a::BroughtField, b::BroughtField) = refvalue(a) == refvalue(b)

implies_blueprint_for(bf::BroughtField, c) = implies_blueprint_for(refvalue(bf), c)

#-------------------------------------------------------------------------------------------
# Checked call to implicit constructor, supposed to yield a consistent blueprint.
function implicit_constructor_for(
    expected_C::CompType,
    ValueType::DataType,
    args::Tuple,
    kwargs::NamedTuple,
    rhs::Any,
)
    bcf(m) = BroughtConvertFailure{ValueType}(expected_C, m, rhs)
    err(m) = throw(bcf(m))
    # TODO: make this constructor customizeable depending on the value.
    cstr = isabstracttype(expected_C) ? expected_C : singleton_instance(expected_C)
    # This needs to be callable.
    isempty(methods(cstr)) && err("'$cstr' is not (yet?) callable. \
                                    Consider providing a \
                                    blueprint value instead.")
    bp = try
        cstr(args...; kwargs...)
    catch e
        if e isa Base.MethodError
            akw = join(args, ", ")
            if !isempty(kwargs)
                akw *=
                    "; " * join(
                        # Wow.. is there anything more idiomatic? ^ ^"
                        Iterators.map(
                            pair -> "$(pair[1]) = $(pair[2])",
                            zip(keys(kwargs), values(kwargs)),
                        ),
                        ", ",
                    )
            end
            throw(bcf("No method matching $cstr($akw). \
                       (See further down the stacktrace.)"))
        end
        rethrow(e)
    end

    # It is a bug in the component library (introduced by framework users)
    # if the implicit constructor yields a wrong value.
    function bug(m)
        red, res = (crayon"bold red", reset)
        err("Implicit blueprint constructor $m\n\
             $(red)This is a bug in the components library.$res")
    end
    bp isa Blueprint || bug("did not yield a blueprint, \
                             but: $(repr(bp)) ::$(typeof(bp)).")
    V = system_value_type(bp)
    V == ValueType || bug("did not yield a blueprint for '$ValueType', but for '$V': $bp.")
    comps = componentsof(bp)
    length(comps) == 1 || bug("yielded instead a blueprint for: [$(join(comps, ", "))].")
    C = first(comps)
    C <: expected_C || bug("yielded instead a blueprint for: $C.")
    bp
end

#-------------------------------------------------------------------------------------------
# Errors associated to the above checks.

# Error when implicitly using default constructor
# to convert arbitrary input to a brought field.
struct BroughtConvertFailure{V}
    BroughtComponent::CompType{V}
    message::String
    rhs::Any
end

# Specialize error when it occurs in the context
# of a field assignment on the host blueprint.
struct BroughtAssignFailure{V}
    HostBlueprint::Type{<:Blueprint{V}}
    fieldname::Symbol
    fail::BroughtConvertFailure{V}
end

struct UnimplementedImpliedMethod{V}
    HostBlueprint::Type{<:Blueprint{V}}
    BroughtSuperType::CompType{V}
    ImpliedSubType::CompType{V} # Subtypes the above.
end

function Base.showerror(io::IO, e::BroughtConvertFailure)
    (; BroughtComponent, message, rhs) = e
    print(
        io,
        "Failed to convert input \
         to a brought blueprint for $(cc(BroughtComponent)):\n$message\n\
         Input was: $(repr(rhs)) ::$(typeof(rhs))",
    )
end

function Base.showerror(io::IO, e::BroughtAssignFailure)
    (; HostBlueprint, fieldname, fail) = e
    (; BroughtComponent, message, rhs) = fail
    print(
        io,
        "Failed to assign to field $(fc(fieldname)) of $(bc(HostBlueprint)) \
         supposed to bring component $(cc(BroughtComponent)):\n$message\n\
         RHS was: $(repr(rhs)) ::$(typeof(rhs))",
    )
end

function Base.showerror(io::IO, e::UnimplementedImpliedMethod{V}) where {V}
    red = crayon"red"
    (; HostBlueprint, BroughtSuperType, ImpliedSubType) = e
    print(
        io,
        "A method has been specified to implicitly bring component $(cc(BroughtSuperType)) \
         from $(bc(HostBlueprint)) blueprints, \
         but no method is specialized \
         to implicitly bring its subtype $(cc(ImpliedSubType)).\n\
         $(red)This is a bug in the components library.$reset",
    )
end

# ==========================================================================================
#  Display.

# Only display full relative path to component name in this context.
comp_name_or_path(C::CompType, level, col) =
    if level == 0
        fmt_compname(comp_path(C); col)
    else
        fmt_compname(strip_compname(nameof(C)); col)
    end

# Special-case the single-provided-component case.
function provided_comps_display(bp::Blueprint, level, col)
    comps = map(C -> comp_name_or_path(C, level, col), componentsof(bp))
    if length(comps) == 1
        "$(first(comps))"
    else
        "{$(join(comps, ", "))}"
    end
end

# Hooks to specialize in case blueprint field values need special display.
display_blueprint_field_short(io::IO, value, bp::Blueprint, ::Val) =
    display_blueprint_field_short(io, value, bp)
# Ignore field name by default.
display_blueprint_field_short(io::IO, value, ::Blueprint) = print(io, value)

function display_blueprint_field_long(
    io::IO,
    value,
    bp::Blueprint,
    ::Val{name},
    level,
) where {name}
    display_blueprint_field_long(io, value, bp, Val(name))
end

# Ignore level by default, then field name.
display_blueprint_field_long(io::IO, value, bp::Blueprint, ::Val) =
    display_blueprint_field_long(io, value, bp)
display_blueprint_field_long(io::IO, value, ::Blueprint) = print(io, value)

# Special-casing brought fields.
function Base.show(io::IO, ::Type{<:BroughtField{C,V}}) where {C,V}
    print(io, "$grayed<brought field type for $reset$component_color$C$reset$grayed>$reset")
end
Base.show(io::IO, bf::BroughtField) = display_blueprint_field_short(io, bf)
Base.show(io::IO, ::MIME"text/plain", bf::BroughtField) =
    display_blueprint_field_long(io, bf, 0)

# Default display is the same regardless of surrounding blueprint / field name.
display_blueprint_field_short(io::IO, bf::BroughtField, ::Blueprint, ::Val) =
    display_blueprint_field_short(io::IO, bf::BroughtField)

function display_blueprint_field_short(io::IO, bf::BroughtField)
    value = refvalue(bf)
    if isnothing(value)
        print(io, "$grayed<$nothing>$reset")
    elseif value isa CompType
        print(io, value)
    elseif value isa Blueprint
        display_short(io, value)
    else
        throw("unreachable: invalid brought blueprint field value: \
               $(repr(value)) ::$(typeof(value))")
    end
end

display_blueprint_field_long(io::IO, bf::BroughtField, ::Blueprint, ::Val, level) =
    display_blueprint_field_long(io, bf, level)

function display_blueprint_field_long(io::IO, bf::BroughtField, level)
    value = refvalue(bf)
    if isnothing(value)
        print(io, "$grayed<no blueprint brought>$reset")
    elseif value isa CompType
        print(io, "$grayed<implied blueprint for $reset")
        print(io, comp_name_or_path(value, level, true))
        print(io, "$grayed>$reset")
    elseif value isa Blueprint
        print(io, "$grayed<embedded $reset")
        display_long(io, value, level)
        print(io, "$grayed>$reset")
    else
        throw("unreachable: invalid brought blueprint field value: \
               $(repr(value)) ::$(typeof(value))")
    end
end

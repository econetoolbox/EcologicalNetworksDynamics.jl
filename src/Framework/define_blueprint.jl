"""
Define a new blueprint.

Caller defines the blueprint struct
(before the corresponding components are actually defined),
and associated late_check/expand!/etc. methods the way they wish,
and then calls:

```jl
define_blueprint(
    TypeName,
    "short string answering 'expandable from'";
    depends = [component, component => reason, ..],
)
```

to record their type as a blueprint.
"""
function define_blueprint(B::DataType, shortline::Option{String} = nothing; depends = [])

    err(mess) = throw(ItemError(:blueprint, B, mess))

    #---------------------------------------------------------------------------------------
    # Inputs checks.

    # Use the given blueprint type to infer system value type.
    isabstracttype(B) && err("Cannot define blueprint from an abstract type: `$B`.")
    B <: Blueprint || err("Not a subtype of `$Blueprint`: `$B`.")
    V = system_value_type(B)
    specified_as_blueprint(B) &&
        err("Type `$B` already marked as a blueprint for systems of `$V`.")

    # Extract possible required components.
    deps = check_reasons(depends, V, "Required component", err)

    #---------------------------------------------------------------------------------------
    # Guard against dependency redundancies.
    checked_deps = triangular_vertical_guard(deps, V, err)

    #---------------------------------------------------------------------------------------
    # At this point, all necessary information
    # should have been parsed, evaluated and checked.
    # The only remaining code to generate and evaluate
    # is the code required for the system to work correctly.

    # Setup expansion dependencies.
    eval(quote
        Framework.expands_from(::$B) = $checked_deps

        # Enhance display.
        Base.show(io::IO, b::$B) = display_short(io, b)
        Base.show(io::IO, ::MIME"text/plain", b::$B) = display_long(io, b, 0)

        function Framework.display_short(io::IO, bp::$B)
            comps = provided_comps_display(bp, 0, false)
            print(io, "$comps:$(nameof($B))(")
            for (i, name) in enumerate(fieldnames($B))
                i > 1 && print(io, ", ")
                print(io, "$name: ")
                # Dispatch on both (bp, name) and field value to allow
                # either kind of specialization.
                value = getfield(bp, name)
                display_blueprint_field_short(io, value, bp, Val(name))
            end
            print(io, ")")
        end

        function Framework.display_long(io::IO, bp::$B, level)
            comps = provided_comps_display(bp, level, true)
            g = level == 0 ? "" : grayed
            print(
                io,
                "$(g)blueprint for$reset $comps: \
                 $blueprint_color$(nameof($B))$reset {",
            )
            preindent = repeat("  ", level)
            level += 1
            indent = repeat("  ", level)
            names = fieldnames($B)
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
    end)

    # Record to avoid multiple calls to `define_blueprint(A)`.
    if !isnothing(shortline)
        eval(quote
            Framework.shortline(io, ::Type{$B}) = print(io, $shortline)
        end)
    end
    eval(quote
        Framework.specified_as_blueprint(::Type{$B}) = true # Seal.
    end)

end
export define_blueprint

#-------------------------------------------------------------------------------------------
# Minor stubs for the generated code evaluation to work.

specified_as_blueprint(B::Type{<:Blueprint}) = false

# Stubs for display methods.
function display_short end
function display_long end

# ==========================================================================================
#  Display.

# Only display full relative path to component name in this context.
function comp_name_or_path(c::CompRef, level, col)
    C = component_type(c)
    if level == 0
        fmt_compname(comp_path(C); col)
    else
        fmt_compname(strip_compname(nameof(C)); col)
    end
end

# Special-case the single-provided-component case.
function provided_comps_display(bp::Blueprint, level, col)
    comps = map(componentsof(bp)) do C
        comp_name_or_path(C, level, col)
    end
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
display_blueprint_field_short(io::IO, value, ::Blueprint) = print(io, repr(value))

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

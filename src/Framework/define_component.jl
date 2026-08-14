"""
Define a new component.

Caller defines possible abstract component supertype,
and/or some blueprints types providing only the created component,
then calls:

```jl
define_component(
    :Name,
    ValueType,
    mod;
    (super = SuperComponentType,)?
    requires = [component, component => reason, ..],
    blueprints = [:name => Type, ..],
)
```

This should be approximately equivalent to the following code:

```jl
# Component type.
struct _Name <: SuperComponentType (or Component{ValueType})
    Blueprint1::Type{Blueprint{ValueType}}
    Blueprint2::Type{Blueprint{ValueType}}
    # ...
end

# Component singleton value.
const Name = _Name(
  BlueprintType1,
  BlueprintType2,
  # ...
)
singleton_instance(::Type{_Name}) = Name

# Base blueprints.
componentsof(::Blueprint1) = (_Name,)
componentsof(::Blueprint2) = (_Name,)
# ...

requires(::Type{_Name}) = ...
```
"""
function define_component(
    Name::Symbol,
    V::DataType,
    mod::Module;
    super = Component{V},
    requires = [],
    blueprints = [],
)

    err(mess) = throw(ItemError(:component, Name, mess))

    #---------------------------------------------------------------------------------------
    # Input checks.

    isdefined(mod, Name) && err("Cannot define component `$Name`: name already defined.")
    check_component(super, V, DataType, "Checking super-component")

    requires = check_reasons(requires, V, "Required component", err)
    blueprints = map(enumerate(blueprints)) do (i, bp)
        if bp isa Module
            bp
        else
            name, bp = try
                a, b = bp
                a, b
            catch _
                err("Not a `name => blueprint` pair: $(repr(bp)) ::$(typeof(bp))")
            end
            name = check_type(name, "Blueprint name [$i]", err, Symbol)
            bp = check_blueprint_type(bp, V, "Blueprints list [$i]", err)
            (name, bp)
        end
    end

    # Check that consistent required component types have been specified.
    reqs = triangular_vertical_guard(requires, V, err)

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
                B isa DataType && B <: Blueprint{V} || continue
                push!(bps, (name, B))
            end
            isempty(bps) && err("Module `$spec` exports no blueprint for `$V`.")
            bps
        else
            [spec] # Only one (name, B) pair has been explicitly provided.
        end
        for (name, B) in blueprints
            # Triangular-check.
            for (other, Other) in base_blueprints
                other == name && err("Base blueprint $(repr(other)) \
                                      both refers to `$Other` and to `$B`.")
                Other == B && err("Base blueprint `$B` bound to \
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
    ctype = Symbol(:_, Name)
    str = quote
        struct $ctype <: $super end
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
        const $Name = $cstr
        $Name
    end
    CompInstance = mod.eval(cstr)
    TC = Type{CompType} # (or would trigger 'local variable cannot be used in closure decl')
    # Connect instance to type.
    eval(quote
        $F.singleton_instance(::$TC) = $CompInstance
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
            F.componentsof(::$B) = ($CompType,)
        end)
    end

    # Setup the components required.
    iter() = CompsReasons{V}(k => v for (k, v) in reqs) # Copy to avoid leaks.
    eval(quote
        F.requires(::$TC) = $iter()
    end)
    CompInstance
end
export define_component

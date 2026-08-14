"""
Components are not values, conceptually,
but they are reified here as julia *singletons types*
whose corresponding blueprints associate to.

No concrete component type can be added twice to the system.

When user wants to add components to the system,
they provide a blueprint value which is then *expanded* into components.

Components may 'require' other components,
because the data they represent are meaningless without them.
If A requires B, it means that A cannot be added in a system with no B.

Components also 'conflict' with each other:
because the data they represent make no sense within their context.
If A conflicts with B, it means that an error should be raised
to prevent from adding A in a system with B.

Component types can be structured with julia's abstract type hierarchy:

  - Conflicting with an abstract component A
    means conflicting with any component subtyping A.

  - If component B subtypes A, then A and B cannot conflict with each other.

It is not currently possible for an abstract component to 'require'.
This might be implemented in the future for a convincingly motivated need,
at the cost of extending the `define_component()` function to produce abstract types.
"""
Component

# Retrieve type from either instance or the type itself.
component_type(C::CompType) = C
component_type(c::Component) = typeof(c)
component_type(x::Any) =
    argerr("Not a component or a component type: $(repr(x)) ::$(typeof(x))")

# Component types being singleton, we *can* infer the value from the type at runtime,
# provided it is not abstract.
singleton_instance(c::Component) = c
singleton_instance(C::CompType) = throw("No concrete singleton instance of '$C'.")

# Extract underlying system wrapped value type from a component.
system_value_type(::CompRef{V}) where {V} = V

# Typecheck regardless of the instance/type.
isacomponent(::CompType) = true
isacomponent(::Component) = true
isacomponent(::Any) = false

#-------------------------------------------------------------------------------------------
# Requirements.

# When specifying a 'component' requirement,
# possibly invoke a 'reason' for it.
# Requirements need to be specified in terms of component types
# because it is possible to require *abstract* components.
const Reason = Option{String}
const CompsReasons{V} = OrderedDict{CompType{V},Reason}

# Specify which components are needed for the focal one to make sense.
requires(::CompType{V}) where {V} = () # Require nothing by default.
requires(c::Component) = requires(typeof(c))

# List all possible blueprints types providing the component.
blueprints(C::CompType{V}) where {V} = throw("No blueprint type specified for $C.")
blueprints(c::Component{V}) where {V} = throw("No blueprint type specified for $c.")

# ==========================================================================================
# Conflicts.

# Components that contradict each other can be grouped into mutually exclusive clusters.
# The clusters need to be defined *after* the components themselves,
# so they can all refer to each other
# as a clique of incompatible nodes in the components graph.
conflicts_(::CompType{V}) where {V} = CompsReasons{V}()
conflicts_(c::Component) = conflicts_(typeof(c))
# When specialized, the above method yields a reference to underlying value,
# updated according to this module's own logic. Don't expose.

#-------------------------------------------------------------------------------------------
# Raise error based on "vertical" subtyping relations.
# (factorizing out a common check pattern)

are_subtypes(A::CompType, B::CompType) = (A <: B) ? (A, B) : (B <: A) ? (B, A) : nothing

# The provided function yields the error to emit in case the inputs subtype each other.
function vertical_guard(A::CompType, B::CompType, diverging_err::Function)
    vert = are_subtypes(A, B)
    isnothing(vert) && return
    sub, sup = vert
    diverging_err(sub, sup)
end

# Provide one special function to error in case inputs are identical.
function vertical_guard(A::CompType, B::CompType, err_same::Function, err_diff::Function)
    vert = are_subtypes(A, B)
    isnothing(vert) && return
    sub, sup = vert
    sub === sup && err_same()
    err_diff(sub, sup)
end

#-------------------------------------------------------------------------------------------
# The 'conflicts_' mapping entries are either abstract or concrete component,
# which makes checking information for one particular component not exactly straighforward.

# (for some reason this is absent from Base)
function supertypes(T::Type)
    S = supertype(T)
    S === T ? (T,) : (T, supertypes(S)...)
end

# Iterate over all conflicts for one particular component.
# yields (conflict_key, conflicting_component, reason)
# The yielded conflict key may be a supercomponent of the focal one.
function all_conflicts(C::CompType)
    supers = I.filter(T -> T !== Any, supertypes(C))
    Iterators.flatten(I.map(supers) do Sup
        entries = conflicts_(Sup)
        I.map(entries) do (k, v)
            (Sup, k, v)
        end
    end)
end

# ==========================================================================================
# Triggers.

# Associate particular components combinations
# with callbacks that will be called immediately after these combinations become available.
# {ValueType => {Component combination => [triggered functions]}}
triggers_(::Type{V}) where {V} = OrderedDict{Set{CompType{V}},OrderedSet{Function}}()
# (same reference/specialization logic as `conflicts_`)

# Setup a trigger.
# The trigger callback signature is either
#   trig(::V)
#   trig(::V, ::System{V}) # (created if missing)
# and is guaranteed to be called as soon as the given combination of components
# becomes available in the system.
function add_trigger!(components, fn::Function)
    V = nothing
    first = nothing
    set = Set()
    for comp in components
        C = component_type(comp)

        # Guard against inconsistent target values.
        if isnothing(V)
            V = system_value_type(C)
            first = comp
        else
            aV = system_value_type(C)
            aV == V || argerr("Both components for '$V' and '$aV' \
                               provided within the same trigger: $first and $comp.")
        end

        # Triangular-check against redundancies.
        for already in set
            vertical_guard(
                C,
                already,
                () -> argerr("Component $comp specified twice in the same trigger."),
                (sub, sup) -> argerr("Both component $sub and its supertype $sup \
                                      specified in the same trigger."),
            )
        end

        push!(set, C)
    end

    # Guard against inconsistent signatures.
    if !hasmethod(fn, Tuple{V,System{V}})
        if hasmethod(fn, Tuple{V})
            # Append method for consistency.
            eval(quote
                (::typeof($fn))(v::$V, ::System{$V}) = $fn(v)
            end)
        else
            argerr("Missing expected method on the given trigger function: $fn(::$V).")
        end
    end

    current = triggers_(V) # Creates a new empty value if falling back on default impl.
    if isempty(current)
        # Specialize to always yield the right reference.
        eval(quote
            triggers_(::Type{$V}) = $current
        end)
    end

    # Append trigger to this particular combination.
    fns = if haskey(current, set)
        current[set]
    else
        current[set] = OrderedSet{Function}()
    end
    fn in fns && argerr("Function '$fn' already added to triggers for combination \
                         {$(join(sort(collect(set); by=T->T.name.name), ", "))}.")
    push!(fns, fn)

    nothing
end
export add_trigger!

# ==========================================================================================
# Display extension points.

compname(C::CompType) = "<$(C.name.name)>" # Singletons *types* in brackets.
compname(c::Component) = String(typeof(c).name.name)
function compdisplay(io::IO, cr::CompRef; color = false)
    s, e = color ? (component_color, reset) : ("", "")
    name = compname(cr)
    print(io, "$s$name$e")
end
compdisplay(cr; kwargs...) = sprint(cr) do io, cr
    compdisplay(io, cr; kwargs...)
end

Base.show(io::IO, C::Type{<:Component}) = F.compdisplay(io, C; color = false)
Base.show(io::IO, c::Component) = F.compdisplay(io, c; color = false)

function Base.show(io::IO, ::MIME"text/plain", C::Type{<:Component})
    V = system_value_type(C)
    F.compdisplay(io, C; color = true)
    print(io, " $black(component type for $V)$reset")
end

# Helpful display resuming base blueprint types for this component,
# assuming it has been generated by the above.
function Base.show(io::IO, ::MIME"text/plain", c::Component)
    V = system_value_type(c)
    names = fieldnames(typeof(c))
    cd = compdisplay(c; color = true)
    print(io, "$cd $black(component for $V")
    if isempty(names)
        print(io, " with no base blueprint")
    else
        println(io, ", expandable from:")
        for name in names
            B = getfield(c, name)
            print(io, "  $blueprint_color$name$reset$black: $italics")
            shortline(io, B)
            println(io, "$reset$black,")
        end
    end
    print(io, ")$reset")
end

shortline(io, B::Type{<:Blueprint}) = @invoke show(io, B::DataType)

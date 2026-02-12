# Blueprint provide components by expanding into them within a system.
#
# The components added during blueprint expansion depend on the blueprint value.
#
# The data inside the blueprint is only useful to run the internal `expand!()` method once,
# and must not lend caller references to the system
# or the internal state could possibly be corrupted later.
#
# Blueprint values may 'bring' other blueprints than themselves,
# because they contain enough data to do so.
# This loosely feels like "sub-components", although it is more subtle.
# There are two ways for blueprints to bring each other:
#
#   - Either they 'embed' other blueprints as sub-blueprints,
#     which expand as part of their own expansion process.
#     It is an error to embed a blueprint for a component already in the system.
#
#   - Or they 'imply' other blueprints for designated components,
#     which could be calculated from the data they contain if needed.
#     This does not need to happen if the components provided by the implied blueprints
#     are already in the system.
#     A blueprint does not 'imply' another specific blueprint,
#     but it 'implies' *some* blueprint bringing the other specific components.
#     Implying an abstract component means implying any blueprint
#     bringing a concrete subtype of this component.
#
# Whether a brought blueprint is embedded or implied
# depends on the bringer value.
# For instance, it can be implied if user has not specified brought-blueprint data,
# and embedded if user has explicitly asked that it be.
#
# Blueprint may also require that other components be present
# for their expansion process to happen correctly,
# even though the components they bring actually do not.
# This blueprint-level requirement is specified by the 'expands_from' function.
# Expanding-from an abstract component A is expanding from any component subtyping A.

# Every blueprint provides only concrete components, and at least one.
struct UnspecifiedComponents{B<:Blueprint} end
componentsof(::B) where {B<:Blueprint} = throw(UnspecifiedComponents{B}())

system_value_type(::Type{<:Blueprint{V}}) where {V} = V
system_value_type(::Blueprint{V}) where {V} = V

#-------------------------------------------------------------------------------------------
# Requirements.

# Return non-empty list if components are required
# for this blueprint to expand,
# even though the corresponding component itself would make sense without these.
expands_from(::Blueprint{V}) where {V} = () # Require nothing by default.
# The above is specialized by hand by framework users,
# so make its return type flexible,
# guarded by the below.
function checked_expands_from(bp::Blueprint{V}) where {V}
    err(x) = throw(InvalidBlueprintDependency("Invalid expansion requirement. \
                                               Expected either a component for $V \
                                               or (component, reason::String), \
                                               got instead: $(repr(x)) ::$(typeof(x))."))
    to_reqreason(x) =
        if x isa Component{V}
            (typeof(x), nothing)
        elseif x isa CompType{V}
            (x, nothing)
        else
            req, reason = try
                q, r = x
                q, (isnothing(r) ? r : String(r))
            catch
                err(x)
            end
            if req isa Component{V}
                (typeof(req), reason)
            elseif req isa CompType{V}
                (req, reason)
            else
                err(x)
            end
        end
    x = expands_from(bp)
    try
        [to_reqreason(x)]
    catch
        Iterators.map(to_reqreason, x)
    end
end
struct InvalidBlueprintDependency <: Exception
    message::String
end

# List brought blueprints.
# Yield blueprint values for embedded blueprints.
# Yield component types for implied blueprints (possibly abstract).
brought(b::Blueprint) = throw("Blueprints brought by $(typeof(b)) are unspecified.")
# Implied blueprints need to be constructed from the value on-demand,
# for a target component.
# Define no default method, so it can be checked
# whether it has been set from within the @blueprint macro.
function implied_blueprint_for end # (blueprint, comptype) -> blueprint for this component.
# Raise this error when "brought" blueprints can be 'embedded' or 'missing' but not implied.
struct _CannotImplyConstruct <: Exception end
cannot_imply_construct() = throw(_CannotImplyConstruct())
function checked_implied_blueprint_for(b::Blueprint, C::CompType)
    bp = implied_blueprint_for(b, C)
    if !any(comp -> comp <: C, componentsof(bp))
        throw("Blueprint $(typeof(b)) is supposed to imply a blueprint for $C,
               but it implied a blueprint for $(collect(componentsof(bp))) instead:\n
               $b\n --- implied --->\n$bp")
    end
    bp
end
# Query.
implies_blueprint_for(b::Blueprint, C::CompType) =
    hasmethod(implied_blueprint_for, Tuple{typeof(b),C})
implies_blueprint_for(b::Blueprint, c::Component) = implies_blueprint_for(b, typeof(c))


#-------------------------------------------------------------------------------------------
# Conflicts.

# Assuming that all component addition / blueprint expansion conditions are met,
# and that brought blueprints have already been expanded,
# verify that the internal system value can still receive it.
# Framework users will use this method to verify
# that the blueprint received matches the current system state
# and that it makes sense to expand within in.
# The objective is to avoid failure during expansion,
# as it could result in inconsistent system state.
# Raise the dedicated blueprint check exception if not the case.
# On success, return arbitrary data useful for `expand!`.
# NOTE: a failure during late check does not compromise the system state consistency,
#       but it does result in that not all blueprints
#       brought by the toplevel added blueprint
#       be added as expected.
#       This is to avoid the need for making the system mutable and systematically fork it
#       to possibly revert to original state in case of failure.
#       TODO: would a swap!(::Network, ::Network) help?
late_check(_, ::Blueprint) = nothing # No particular constraint to enforce by default.

# Same, but *before* brought blueprints are expanded.
# When this runs, it is guaranteed
# that there is no conflicting component in the system
# and that all required components are met,
# but, as it cannot be assumed that required components have already been expanded,
# the check should not depend on the system value.
# Issue `CheckError` on failure.
# TODO: add formal test for this.
early_check(::Blueprint) = nothing # No particular constraint to enforce by default.

# The expansion step is when the wrapped system value is finally modified,
# based on the information contained in the blueprint,
# to feature the provided components.
# This is only called if all component addition conditions are met
# and the above check passed.
# Expansion feeds from arbitrary data produced by a success in `late_check`.
# This function must not fail or the system may end up in a corrupt state.
# TODO: must it also be deterministic?
#       Or can a random component expansion happen
#       if infallible and based on consistent blueprint input.
#       Note that random expansion would result in:
#       (System{Value}() + blueprint).property != (System{Value}() + blueprint).property
#       which may be confusing.
expand!(_, ::Blueprint, data) = nothing # Expanding does nothing by default.

# NOTE: the above signatures for default functions *could* be more strict
# like eg. `check(::V, ::Blueprint{V}) where {V}`,
# but this would force framework users to always specify the first argument type
# or concrete calls to `check(system, myblueprint)` would be ambiguous.

# When components "optionally depend" on others,
# it may be useful to check whether they are present in the system
# within the methods above.
# To this end, an optional, additional argument
# can be received with a reference to the system,
# and can be queried for eg. `has_component(system, component)`.
# This third argument is ignored by default,
# unless in overriden methods.
# Issue `CheckError` on failure.
late_check(v, b::Blueprint, _) = late_check(v, b)
expand!(v, b::Blueprint, data, _) = expand!(v, b, data)

# ==========================================================================================
# Explicit terminal display.
function Base.show(io::IO, ::MIME"text/plain", B::Type{<:Blueprint{V}}) where {V}
    B = stripped_path(B)
    print(
        io,
        "$blueprint_color$B$reset \
         $grayed(blueprint type for $(nameof(System)){$V})$reset",
    )
end

function Base.showerror(io::IO, ::UnspecifiedComponents{B}) where {B}
    print(io, "Unspecified provided components for '$(repr(B))'.")
end

# Improve field name error.
Base.getproperty(b::Blueprint, name::Symbol) =
    if hasproperty(b, name)
        @invoke getproperty(b::Any, name)
    else
        error("blueprint $(typeof(b)) has no field $(repr(name))")
    end

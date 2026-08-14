"""
Blueprint provide components by expanding into them within a system.

The components added during blueprint expansion depend on the blueprint value.

The data inside the blueprint is only useful to run the internal `expand!()` method once,
and must not lend caller references to the system
or the internal state could possibly be corrupted later.

Blueprint values may 'imply' other blueprints than themselves,
because they contain enough information to do so.
This loosely feels like "sub-components", although it is more subtle.
When a blueprint implies other blueprints for designated components,
they could be calculated from the data it contains if needed.
This does not need to happen if the components provided by the implied blueprints
are already in the system.
A blueprint does not 'imply' another specific blueprint,
but it 'implies' *some* blueprint bringing the other specific components.
Implying an abstract component means implying any blueprint
bringing a concrete subtype of this component.

Blueprint may also require that other components be present
for their expansion process to happen correctly.
This blueprint-level requirement is specified by the 'expands_from' function.
Expanding-from an abstract component A is expanding from any component subtyping A.

Every blueprint provides only concrete components, and at least one.
"""
Blueprint

struct UnspecifiedComponents{B<:Blueprint} end
componentsof(::B) where {B<:Blueprint} = throw(UnspecifiedComponents{B}())

system_value_type(::Type{<:Blueprint{V}}) where {V} = V
system_value_type(::Blueprint{V}) where {V} = V

#-------------------------------------------------------------------------------------------
# Requirements.

"""
Return non-empty list if components are required for this blueprint to expand,
even though the corresponding component itself would make sense without these.
"""
expands_from(::Blueprint{V}) where {V} = () # Require nothing by default.

# The above is specialized by hand by framework users,
# so make its return type flexible, guarded by the below.
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

"""
List implied blueprints by yielding the corresponding component types.
Yielding components instances instead is supported.
Expected signature for a component `C` of type `_C`:
`function(::Blueprint)::"Iterable"{Union{C, _C}}`.
"""
implied(::Blueprint) = () # Default to nothing implied.

"""
Implied blueprints need to be constructed from the focal blueprint value on-demand
for every target component. This is called "implicit blueprint construction".
Expected signature for a component `C` of type `_C`:
`function(::Blueprint, ::Type{_C})::Blueprint`.
Ergonomy quirk: `Type{..}` is required here
because it needs to work consistently with abstract components:
the `add` procedure will only call the method with component types.
"""
function implied_blueprint_for end

# Define no default method to the above, so it can be queried
# whether one has been set during `define_blueprint()` call.
# (focal blueprint, component) -> blueprint for this component.
implies_blueprint_for(b::Blueprint, C::CompType) =
    hasmethod(implied_blueprint_for, Tuple{typeof(b),Type{C}})

#-------------------------------------------------------------------------------------------
# Conflicts.

"""
Component authors use this method to verify blueprint value
before implied blueprints are expanded.
When this runs, it is guaranteed that there is no conflicting component in the system
and that all required components are met, but,
as it cannot be assumed that required components have already been expanded,
the check cannot depend on the system value.
Issue `InputError` on failure.
On success, return arbitrary data useful for `late_check`.
"""
# TODO: add formal test for this.
early_check(::Blueprint) = nothing # No particular constraint to enforce by default.

"""
Assuming that all component addition / blueprint expansion conditions are met,
and that implied blueprints have already been expanded,
verify that the internal system value can still receive it.
Component authors use this method to verify
that the blueprint received matches the current system state
and that it makes sense to expand within in.
The objective is to avoid failure during expansion,
as it could result in inconsistent system state.
Issue `InputError` on failure.
On success, return arbitrary data useful for `expand!`.

*NOTE*: a failure during late check does not compromise the system state consistency,
but it does result in that not all blueprints brought by the toplevel added blueprint
be added as expected.
This is to avoid the need for making the system mutable and systematically fork it
to possibly revert to original state in case of failure.
"""
# TODO: would a swap!(::Network, ::Network) help in making add! transactional?
late_check(s, bp::Blueprint, _early_check_data) = late_check(s, bp)
late_check(_, ::Blueprint) = nothing # Ignore additional data by default.

"""
Assuming that late_check passed,
transform its passed data into anything useful to `expand!`.
Failure to lower can only be a bug in the component library,
but it does not compromise system state because `expand!` has not yet started.
"""
lower(_, ::Blueprint, late_check_data) = late_check_data # Pass unchanged by default.

"""
The expansion step is when the wrapped system value is finally modified,
based on the information contained in the blueprint,
to feature the provided components.
This is only called if all component addition conditions are met
and the above check passed.
Expansion feeds from arbitrary data produced by success in `late_check`.
This function must not fail or the system may end up in a corrupt state.
"""
# TODO: must it also be deterministic?
#       Or can a random component expansion happen
#       if infallible and based on consistent blueprint input.
#       Note that random expansion would result in:
#       (System{Value}() + blueprint).property != (System{Value}() + blueprint).property
#       which may be confusing.
expand!(s, bp::Blueprint, _lower_data) = expand!(s, bp) # Ignore data..
expand!(_, ::Blueprint) = nothing # ..and do nothing by default.

# NOTE: the above signatures for default functions *could* be more strict
# like eg. `check(::System{V}, ::Blueprint{V}) where {V}`,
# but this would force framework users to always specify the first argument type
# or concrete calls to `check(system, myblueprint)` would be ambiguous.

# ==========================================================================================
# Display.
function Base.show(io::IO, ::MIME"text/plain", B::Type{<:Blueprint})
    V = system_value_type(B)
    B = stripped_path(B)
    print(
        io,
        "$blueprint_color$B$reset \
         $gray(blueprint type for $(nameof(System)){$V})$reset",
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

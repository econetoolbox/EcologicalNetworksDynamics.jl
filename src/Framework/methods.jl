"""
Methods add functionalities to the system,
in the sense that components add the *data* while methods add the *code*.

Methods are never "added" onto the system's value. They are already there.
But they come in two styles:

```jl
method(s::System, ..) # Checks that required components are loaded before it runs.
method(v::Value, ..)  # Runs, with undefined behaviour if components are missing.
```

Only the second one needs to be specified by component authors.
and then the `define_method()` function should do the rest (see documentation there).

The polymorphism of methods use julia dispatch over function types.
"""
() # TODO: not sure what to bind that docstring to?

# Methods depend on nothing by default.
depends(S::Type{<:System}, ::Type{<:Function}) = CompType{system_value_type(S)}[]
missing_dependencies_for(fn::Type{<:Function}, s::System) =
    Iterators.filter(depends(typeof(s), fn)) do dep
        !has_component(s, dep)
    end
# Just pick the first one. Return nothing if dependencies are met.
function first_missing_dependency_for(fn::Type{<:Function}, s::System)
    for dep in missing_dependencies_for(fn, s)
        return dep
    end
    nothing
end

# Direct call with the functions themselves.
depends(T::Type, fn::Function) = depends(T, typeof(fn))
missing_dependencies_for(fn::Function, s::System) = missing_dependencies_for(typeof(fn), s)
first_missing_dependency_for(fn::Function, s::System) =
    first_missing_dependency_for(typeof(fn), s)

# Hack flag to avoid interrupting the `Revise` process.
# Raise when done defining methods in the components library.
global REVISING = false # TODO: Is this still needed after refactoring?

# ==========================================================================================
# Dedicated exceptions.

# About method use.
struct MethodError{V} <: SystemException
    name::Union{Symbol,Expr} # Name or Path.To.Name.
    message::String
    MethodError(::Type{V}, n, m) where {V} = new{V}(n, m)
end
function Base.showerror(io::IO, e::MethodError{V}) where {V}
    println(io, "In method `$(e.name)` for `$V`: $(e.message)")
end
metherr(V, n, m) = throw(MethodError(V, n, m))

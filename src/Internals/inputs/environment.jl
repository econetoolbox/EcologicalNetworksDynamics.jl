mutable struct Environment
    T::Float64
end

Base.:(==)(a::Environment, b::Environment) = equal_fields(a, b)

"""
One line Environment display.
"""
function Base.show(io::IO, environment::Environment)
    T = environment.T
    print(io, "Environment(T=$(T)K)")
end

"""
Multiline Environment display.
"""
function Base.show(io::IO, ::MIME"text/plain", environment::Environment)
    println(io, "Environment:")
    print(io, "  T: $(environment.T) Kelvin")
end

"""
    Environment(; T=293.15)

Create environmental parameters of the system.

The environmental parameters are:

  - T the temperature (in Kelvin)
    By default, the carrying capacities of producers are assumed to be 1 while capacities of
    consumers are assumed to be `nothing` as consumers do not have a growth term.

# Examples

```jldoctest
julia> e = Environment() # Default behaviour.
       e.T == 293.15 # Kelvin
true

julia> e = Environment(; T = 300.0)
       e.T == 300.0
true
```

See also [`ModelParameters`](@ref).
"""
Environment(; T = 293.15) = Environment(T)

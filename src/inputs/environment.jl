"""
    Environment(foodweb, K=1, T=293.15)

Create environmental parameters of the system.

The environmental parameters are:
- K the vector of carrying capacities
- T the temperature (in Kelvin)
By default, the carrying capacities of producers are assumed to be 1 while capacities of
consumers are assumed to be `nothing` as consumers do not have a growth term.

# Examples
```jldoctest
julia> foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0]); # species 1 & 2 producers, 3 consumer

julia> environment = Environment(foodweb) # default behavior
K (carrying capacity): 1, ..., nothing
T (temperature in Kelvins - 0C = 273.15K): 293.15 K

julia> environment.K # 1 for producers (1 & 2), nothing for consumers (3)
3-element Vector{Union{Nothing, Real}}:
 1
 1
  nothing

julia> Environment(foodweb, K=2).K # change the default value for producers
3-element Vector{Union{Nothing, Real}}:
 2
 2
  nothing

julia> Environment(foodweb, K=[1,2,nothing]).K # can also provide a vector
3-element Vector{Union{Nothing, Real}}:
 1
 2
  nothing
```

See also [`ModelParameters`](@ref).
"""
function Environment(
    foodweb::FoodWeb;
    K::Union{Tp,Vector{Union{Nothing,Tp}},Vector{Tp}}=1,
    T::Real=293.15
) where {Tp<:Real}

    S = richness(foodweb)

    # Test
    length(K) ∈ [1, S] || throw(ArgumentError("Wrong length: K should be of length 1 or S
        (species richness)."))

    # Format if needed
    length(K) == S || (K = [isproducer(foodweb, i) ? K : nothing for i in 1:S])

    Environment(K, T)
end

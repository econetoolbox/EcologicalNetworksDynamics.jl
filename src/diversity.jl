"""
    richness(solution::Solution; threshold = 0)

Return the number of alive species at each timestep of the simulation.
`solution` is the output of [`simulate`](@ref).
By default, species are considered extinct if their biomass is 0.
But, this `threshold` can be changed using the corresponding keyword argument.

# Examples

Let's start with a simple example where the richness remains constant:

```jldoctest
julia> foodweb = Foodweb([0 0; 1 0])
       m = default_model(foodweb)
       B0 = [0.5, 0.5]
       tmax = 100
       sol = simulate(m, B0, tmax)
       richness_trajectory = richness(sol)
       all(richness_trajectory .== 2) # At each timestep, there are 2 alive species.
true
```

Now let's assume that the producer is extinct at the beginning of the simulation,
while its consumer is not.
We expect to observe a decrease in richness from 1 to 0 over time.

```jldoctest
julia> B0 = [0, 0.5] # The producer is extinct at the beginning.
       sol = simulate(m, B0, 1_000)
       richness_trajectory = richness(sol)
       richness_trajectory[1] == 1 && richness_trajectory[end] == 0
true
```
"""
richness(solution::Solution; threshold = 0) = richness.(solution.u; threshold)
export richness

"""
    richness(biomasses::AbstractVector; threshold = 0)

Return the number of alive species given a biomass vector.
By default, species are considered extinct if their biomass is 0.
But, this `threshold` can be changed using the corresponding keyword argument.

# Examples

```jldoctest
julia> richness([0.2, 0, 0.3]) # Only two species are non-extinct in this biomass vector.
2
```
"""
richness(biomasses::AbstractVector; threshold = 0) = count(>(threshold), biomasses)

"""
    persistence(solution::Solution; threshold = 0)

Fraction of alive species at each timestep of the simulation.
See [`richness`](@ref) for details.

# Examples

```jldoctest
julia> S = 20 # Initial number of species.
       foodweb = Foodweb(:niche; S = 20, C = 0.1)
       m = default_model(foodweb)
       B0 = rand(S)
       sol = simulate(m, B0, 2000)
       all(persistence(sol) .== richness(sol) / S)
true
```
"""
persistence(solution::Solution; threshold = 0) = persistence.(solution.u; threshold)
export persistence

"""
    persistence(biomasses::AbstractVector; threshold = 0)

Fraction of alive species given a biomass vector.
See [`richness`](@ref) for details.
"""
persistence(biomasses::AbstractVector; threshold = 0) =
    richness(biomasses; threshold) / length(biomasses)

"""
    total_biomass(solution::Solution)

Total biomass of a community at each timestep of the simulation.
`solution` is the output of [`simulate`](@ref).

# Example

Let's consider a consumer feeding on a producer,
and let's start the simulation with the producer extinction
so we can observe the consumer's biomass decrease over time.

```jldoctest
julia> foodweb = Foodweb([0 0; 1 0])
       m = default_model(foodweb)
       B0 = [0, 0.5] # The producer is extinct at the beginning.
       sol = simulate(m, B0, 1_000)
       biomass_trajectory = total_biomass(sol)
       biomass_trajectory[1] == 0.5 && biomass_trajectory[end] == 0
true
```
"""
total_biomass(solution::Solution) = total_biomass.(solution.u)
export total_biomass

"""
    total_biomass(biomasses::AbstractVector)

Total biomass of a community given a biomass vector.

# Examples

```jldoctest
julia> total_biomass([0.5, 1.5]) # 0.5 + 1.5 = 2.0
2.0
```
"""
total_biomass(biomasses::AbstractVector) = sum(biomasses)

"""
    shannon_diversity(solution::Solution; threshold = 0)

Shannon diversity index at each timestep of the simulation.
`solution` is the output of [`simulate`](@ref).
Shannon diversity is a measure of species diversity based on the entropy.
According to the Shannon index, for a same number of species,
the more evenly the biomass is distributed among them,
the higher the diversity.

# Example

We start a simple simulation with even biomass distribution,
therefore we expect the Shannon diversity to decrease over time
as the biomass of the species diverge from each other.

```jldoctest
julia> foodweb = Foodweb([0 0; 1 0])
       m = default_model(foodweb)
       B0 = [0.5, 0.5] # Even biomass, maximal shannon diversity.
       sol = simulate(m, B0, 1_000)
       shannon_trajectory = shannon_diversity(sol)
       biomass_trajectory[1] > biomass_trajectory[end]
true
```
"""
shannon_diversity(solution::Solution; threshold = 0) =
    shannon_diversity.(solution.u; threshold)
export shannon_diversity

"""
    shannon_diversity(biomasses::AbstractVector; threshold = 0)

Shannon diversity index given a biomass vector.

Shannon diversity is a measure of species diversity based on the entropy.
According to the Shannon index, for a same number of species,
the more evenly the biomass is distributed among them,
the higher the diversity.

# Example

We consider a simple example with 3 species, but different shannon diversity.

```jldoctest
julia> s1 = shannon_diversity([1, 1, 1])
       s2 = shannon_diversity([1, 1, 0.1])
       s3 = shannon_diversity([1, 1, 0.01])
       s1 > s2 > s3
true
```

We observe as we decrease the biomass of the third species,
the shannon diversity tends to 2, as we tend towards an effective two-species community.
"""
function shannon_diversity(biomasses::AbstractVector; threshold = 0)
    x = filter(>(threshold), biomasses)
    p = x ./ sum(x)
    exp(-sum(p .* log.(p)))
end

# Quantify food webs structural properties.

"""
    richness(p::ModelParameters)

Number of species in the network.

```jldoctest
julia> foodweb = FoodWeb([1 => 2]) # 1 eats 2.
       model = ModelParameters(foodweb)
       richness(model)
2
```

See also [`nutrient_richness`](@ref) and [`total_richness`](@ref).
"""
richness(p::ModelParameters) = richness(p.network)
richness(net::EcologicalNetwork) = richness(get_trophic_adjacency(net))
richness(A::AbstractMatrix) = size(A, 1)

"""
Species indices of the given `network`.
"""
species_indices(p::ModelParameters) = 1:richness(p)

"""
Nutrient indices of the given `network`.
"""
function nutrient_indices(p::ModelParameters)
    n = nutrient_richness(p)
    S = richness(p) # Species richness.
    S .+ (1:n)
end

"""
    nutrient_richness(p::ModelParameters)

Number of nutrients in the model `p`.

```jldoctest
julia> foodweb = FoodWeb([1 => 2]) # 1 eats 2.
       producer_growth = LogisticGrowth(foodweb) # No nutrients.
       model = ModelParameters(foodweb; producer_growth)
       nutrient_richness(model)
0

julia> producer_growth = NutrientIntake(foodweb; n_nutrients = 3) # Include nutrients.
       model_with_nutrients = ModelParameters(foodweb; producer_growth)
       nutrient_richness(model_with_nutrients)
3
```

See also [`richness`](@ref) and [`total_richness`](@ref).
"""
function nutrient_richness(p::ModelParameters)
    pg = p.producer_growth
    isa(pg, NutrientIntake) ? length(pg) : 0
end

"""
    total_richness(p::ModelParameters)

Total richness of the system defined as the sum of the number of species
and the number of nutrients.
If the model `p` does not include nutrient dynamics for producer growth,
then `total_richness` is equivalent the species [`richness`](@ref).

```jldoctest
julia> foodweb = FoodWeb([1 => 2]) # 1 eats 2.
       producer_growth = LogisticGrowth(foodweb)
       model = ModelParameters(foodweb; producer_growth)
       total_richness(model) == richness(model) == 2
true

julia> producer_growth = NutrientIntake(foodweb; n_nutrients = 3) # Include nutrients.
       model_with_nutrients = ModelParameters(foodweb; producer_growth)
       S = richness(model_with_nutrients)
       N = nutrient_richness(model_with_nutrients)
       total_richness(model_with_nutrients) == S + N == 5 # 2 + 3
true
```

See also [`richness`](@ref) and [`nutrient_richness`](@ref).
"""
total_richness(p::ModelParameters) = richness(p) + nutrient_richness(p)

"""
Filter species of the network (`net`) for which `f(species_index, net) = true`.
"""
Base.filter(f, net::EcologicalNetwork) = filter(i -> f(i, net), 1:richness(net))

"""
Transform species of the network (`net`) by applying `f` to each species.
"""
Base.map(f, net::EcologicalNetwork) = map(i -> f(i, net), 1:richness(net))

"""
Is species `i` of the network (`net`) a producer?
"""
isproducer(i, A::AdjacencyMatrix) = isempty(A[i, :].nzval)
isproducer(i, net::FoodWeb) = isproducer(i, net.A)
isproducer(i, net::MultiplexNetwork) = isproducer(i, net.layers[:trophic].A)

"""
Return indices of the producers of the given `network`.
"""
producers(net) = filter(isproducer, net)
producers(A::AbstractMatrix) = (1:richness(A))[all(A .== 0; dims = 2)|>vec]

"""
    predators_of(i, network)

Return indices of the predators of species `i` for the given `network`.

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 0 0; 1 0 0; 1 1 0]);

julia> predators_of(1, foodweb)
2-element Vector{Int64}:
 2
 3

julia> predators_of(2, foodweb)
1-element Vector{Int64}:
 3

julia> predators_of(3, foodweb)
Int64[]
```

See also [`preys_of`](@ref) and [`producers`](@ref).
"""
predators_of(i, A::AdjacencyMatrix) = A[:, i].nzind
predators_of(i, net::FoodWeb) = predators_of(i, net.A)
predators_of(i, net::MultiplexNetwork) = predators_of(i, net.layers[:trophic].A)

"""
Is species `i` of the network (`net`) a predator?
"""
ispredator(i, A::AdjacencyMatrix) = !isproducer(i, A)
ispredator(i, net::FoodWeb) = ispredator(i, net.A)
ispredator(i, net::MultiplexNetwork) = ispredator(i, net.layers[:trophic].A)

"""
Return indices of the predators of the given `network`.
"""
predators(net::EcologicalNetwork) = filter(ispredator, net)
#### end ####

#### Find preys ####
"""
    preys_of(i, network)

Return indices of the preys of species `i` for the given `network`.

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0]);

julia> preys_of(3, foodweb)
2-element Vector{Int64}:
 1
 2

julia> preys_of(1, foodweb) # empty
Int64[]
```

See also [`predators_of`](@ref) and [`producers`](@ref).
"""
preys_of(i, net::FoodWeb) = preys_of(i, net.A)
preys_of(i, net::MultiplexNetwork) = preys_of(i, net.layers[:trophic].A)
preys_of(i, A::AdjacencyMatrix) = A[i, :].nzind

"""
Is species `i` a prey?
"""
isprey(i, A::AdjacencyMatrix) = !isempty(A[:, i].nzind)
isprey(i, net::FoodWeb) = isprey(i, net.A)
isprey(i, net::MultiplexNetwork) = isprey(i, net.layers[:trophic].A)

"""
Return indices of the preys of the network (`net`).
"""
preys(net::EcologicalNetwork) = filter(isprey, net)
preys(A::AbstractSparseMatrix) = [i for i in 1:richness(A) if !isempty(A[:, i].nzval)]

"""
Do species `i` and `j` share at least one prey?
"""
share_prey(i, j, A::AdjacencyMatrix) = !isempty(intersect(preys_of(i, A), preys_of(j, A)))
share_prey(i, j, net::FoodWeb) = share_prey(i, j, net.A)
share_prey(i, j, net::MultiplexNetwork) = share_prey(i, j, net.layers[:trophic].A)

"""
Is species `i` an ectotherm vertebrate?
"""
isvertebrate(i, net::EcologicalNetwork) = net.metabolic_class[i] == "ectotherm vertebrate"

"""
Is species `i` an invertebrate?
"""
isinvertebrate(i, net::EcologicalNetwork) = net.metabolic_class[i] == "invertebrate"

"""
Return indices of the vertebrates of the network (`net`).
"""
vertebrates(net::EcologicalNetwork) = filter(isvertebrate, net)

"""
Return indices of the invertebrates of the network (`net`).
"""
invertebrates(net::EcologicalNetwork) = filter(isinvertebrate, net)

"""
Number of resources species `i` is feeding on.
"""
number_of_resource(i, A::AdjacencyMatrix) = length(A[i, :].nzval)
number_of_resource(i, net::FoodWeb) = number_of_resource(i, net.A)
number_of_resource(i, net::MultiplexNetwork) = number_of_resource(i, net.layers[:trophic].A)

"""
Return a vector where element i is the number of resource(s) of species i.
"""
function number_of_resource(net::EcologicalNetwork)
    [number_of_resource(i, net) for i in 1:richness(net)]
end

"""
    trophic_levels(net::EcologicalNetwork)

Trophic level of each species.

```jldoctest
julia> foodweb = FoodWeb([1 => 2])
       trophic_levels(foodweb) == [2.0, 1.0]
true
```

See also [`top_predators`](@ref) and [`trophic_classes`](@ref).
"""
function trophic_levels(A::AbstractMatrix)
    A = Matrix(A) # Ensure A is dense for inversion.
    S = richness(A)
    out_degree = sum(A; dims = 2)
    D = -(A ./ out_degree) # Diet matrix.
    D[isnan.(D)] .= 0.0
    D[diagind(D)] .= 1.0 .- D[diagind(D)]
    # Solve with the inverse matrix.
    inverse = iszero(det(D)) ? pinv : inv
    inverse(D) * ones(S)
end

trophic_levels(net::EcologicalNetwork) = trophic_levels(get_trophic_adjacency(net))

"""
    top_predators(net::EcologicalNetwork)

Top predator indices (species eaten by nobody) of the given `net`work.

```jldoctest
julia> foodweb = FoodWeb([1 => 2, 2 => 3])
       top_predators(foodweb) == [1]
true
```

See also [`trophic_levels`](@ref) and [`trophic_classes`](@ref).
"""
function top_predators(net::EcologicalNetwork)
    A = get_trophic_adjacency(net)
    top_predators(A)
end

function top_predators(A)
    S = richness(A)
    [i for i in 1:S if all(A[:, i] .== 0)]
end

"""
    trophic_classes(foodweb::FoodWeb)

Categorize each species into three classes:
either `producers`, `intermediate_consumers` or `top_predators`.

```jldoctest
julia> foodweb = FoodWeb([1 => 2, 2 => 3])
       trophic_classes(foodweb)
(producers = [3], intermediate_consumers = [2], top_predators = [1])
```

To access the name of the trophic classes
you can simply call `trophic_classes` without any argument.

```jldoctest
julia> trophic_classes()
(:producers, :intermediate_consumers, :top_predators)
```

See also [`trophic_levels`](@ref) and [`top_predators`](@ref).
"""
function trophic_classes(A; extinct_sp = Set())
    S = richness(A)
    prod = producers(A)
    top_pred = top_predators(A)
    intermediate_cons = setdiff(1:S, union(prod, top_pred))
    # Order here must match the semantics of `trophic_classes()` order.
    class = [prod, intermediate_cons, top_pred]
    if !isempty(extinct_sp) # filter extinct species
        class = [setdiff(cl, extinct_sp) for cl in class]
    end
    names = trophic_classes()
    NamedTuple{names}(class)
end

trophic_classes() = (:producers, :intermediate_consumers, :top_predators)

"""
    remove_species(net::EcologicalNetwork, species_to_remove)

Remove a list of species from a `FoodWeb`, a `MultiplexNetwork` or an adjacency matrix.

# Examples

Adjacency matrix.

```jldoctest
julia> A = [0 0 0; 1 0 0; 1 0 0]
       remove_species(A, [1]) == [0 0; 0 0]
true

julia> remove_species(A, [2]) == [0 0; 1 0]
true
```

`FoodWeb`.

```jldoctest
julia> foodweb = FoodWeb([0 0 0; 1 0 0; 1 0 0]; M = [1, 10, 20])
       new_foodweb = remove_species(foodweb, [2])
       new_foodweb.A == [0 0; 1 0]
true

julia> new_foodweb.M == [1, 20]
true
```

`MultiplexNetwork`.

```jldoctest
julia> foodweb = FoodWeb([0 0 0; 1 0 0; 1 0 0]; M = [1, 10, 20])
       net = MultiplexNetwork(foodweb; A_facilitation = [0 0 0; 1 0 0; 0 0 0])
       new_net = remove_species(net, [2])
       new_net.layers[:trophic].A == [0 0; 1 0]
true

julia> new_net.layers[:facilitation].A == [0 0; 0 0]
true

julia> new_net.M == [1, 20]
true
```
"""
function remove_species(foodweb::FoodWeb, species_to_remove)
    S = richness(foodweb)
    A_new = remove_species(foodweb.A, species_to_remove)
    species_to_keep = setdiff(1:S, species_to_remove)
    M_new = foodweb.M[species_to_keep]
    metabolic_class_new = foodweb.metabolic_class[species_to_keep]
    species_new = foodweb.species[species_to_keep]
    method = foodweb.method
    FoodWeb(A_new, species_new, M_new, metabolic_class_new, method)
end

function remove_species(net::MultiplexNetwork, species_to_remove)
    trophic = convert(FoodWeb, net)
    new_trophic = remove_species(trophic, species_to_remove)
    multi_net = MultiplexNetwork(new_trophic) # no non-trophic interactions yet
    for (name, layer) in net.layers
        A_nti_new = remove_species(layer.A, species_to_remove)
        multi_net.layers[name].A = A_nti_new
        multi_net.layers[name].intensity = layer.intensity
        multi_net.layers[name].f = layer.f
    end
    multi_net
end

function remove_species(A::AbstractMatrix, species_to_remove)
    S = richness(A)
    species_to_keep = setdiff(1:S, species_to_remove)
    n_kept = length(species_to_keep)
    A_simplified = zeros(Integer, n_kept, n_kept)
    for (i_idx, i) in enumerate(species_to_keep), (j_idx, j) in enumerate(species_to_keep)
        A_simplified[i_idx, j_idx] = A[i, j]
    end
    A_simplified
end

"""
    mass_ratio(p::ModelParameters)

Mean predator-prey body mass ratio given the model `p`arameters.
"""
mass_ratio(p::ModelParameters) = mass_ratio(p.network)

"""
    mass_ratio(network::EcologicalNetwork)

Mean predator-prey body mass ratio given the `network`.
"""
function mass_ratio(network::EcologicalNetwork)
    A = get_trophic_adjacency(network)
    M = network.M
    mean((M./M')[findall(A)])
end

# Extend method from Graphs.jl to FoodWeb and MultiplexNetwork.
function Graphs.is_cyclic(net::EcologicalNetwork)
    is_cyclic(SimpleDiGraph(get_trophic_adjacency(net)))
end

function Graphs.is_connected(net::EcologicalNetwork)
    is_connected(SimpleDiGraph(get_trophic_adjacency(net)))
end

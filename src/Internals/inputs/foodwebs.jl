#=
Generating FoodWeb objects
=#

# Aliases for comfort
const AdjacencyMatrix = SparseMatrixCSC{Bool,Int64}
const Label = Union{String,Symbol}

#### Type definition and FoodWeb functions ####
abstract type EcologicalNetwork end
mutable struct FoodWeb <: EcologicalNetwork
    # FROM THE FUTURE - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # The "species" compartment lives here for now,
    # so make all other fields optional:
    # only filled when the corresponding components are added.
    A::Option{AdjacencyMatrix}
    species::Vector{String}
    M::Option{Vector{Float64}}
    metabolic_class::Option{Vector{String}}
    method::Option{String}
    # User can refer to species with names instead of indices.
    _species_index::Dict{Symbol,Int64}
    # Called when expanding "Species" component.
    FoodWeb(names::Vector{Symbol}) = new(
        nothing,
        String.(names), # Match legacy data.
        nothing,
        nothing,
        nothing,
        Dict(s => i for (i, s) in enumerate(names)),
    )
    # Reinject this logic into legacy internals.
    FoodWeb(A, sp, M, mc, mth) =
        new(A, sp, M, mc, mth, Dict(Symbol(s) => i for (i, s) in enumerate(sp)))
end

Base.:(==)(a::FoodWeb, b::FoodWeb) = equal_fields(a, b)

"""
    FoodWeb(
        A::AbstractMatrix;
        species::Vector{<:Label} = default_speciesid(A),
        Z::Real = 1,
        M::Vector{<:Real} = compute_mass(A, Z),
        metabolic_class::Vector{<:Label} = default_metabolic_class(A),
        method::String = "unspecified",
    )

# Generate a `FoodWeb` from an adjacency matrix

This is the most direct way to generate a `FoodWeb`.
You only need to provide an adjacency matrix filled with 0s and 1s,
that respectively indicates the absence or presence of an interaction
between the corresponding species pair.
For instance `A = [0 0; 1 0]` corresponds to a system of 2 species
in which species 2 eats species 1.

```jldoctest
julia> FoodWeb([0 0; 1 0])
FoodWeb of 2 species:
  A: sparse matrix with 1 links
  M: [1.0, 1.0]
  metabolic_class: 1 producers, 1 invertebrates, 0 vertebrates
  method: unspecified
  species: [s1, s2]
```

You can also provide optional arguments e.g. to change the species names.

```jldoctest
julia> foodweb = FoodWeb([0 0; 1 0]; species = ["plant", "herbivore"]);

julia> foodweb.species == ["plant", "herbivore"]
true
```

# Generate a `FoodWeb` from an adjacency list

An adjacency list is an iterable of `Pair`s
(e.g. vector of `Pair`s) or a dictionary.
If the adjacency list is an iterable of `Pair`s,
the first element of each pair is a predator
and the second element of each pair are the preys eaten by the corresponding predator.
If the adjacency list is a dictionary,
keys are predators and values the corresponding preys.

Species can be identified either with `Integer`s corresponding to species indexes
or with labels (`String`s or `Symbol`s) corresponding to the species names.
In the latter case, species will be ordered lexically.
Moreover, if you use labels
the species names will be directly passed to the `FoodWeb.species` field.

```jldoctest
julia> al_names = ["snake" => ("turtle", "mouse")]; # can also be `Symbol`s

julia> al_index = [2 => [1, 3]]; # ~ if sorting species lexically

julia> fw_from_names = FoodWeb(al_names);

julia> fw_from_index = FoodWeb(al_index);

julia> fw_from_names.A == fw_from_index.A == [0 0 0; 1 0 1; 0 0 0]
true

julia> fw_from_names.species == ["mouse", "snake", "turtle"] # ordered lexically
true
```

# Generate a `FoodWeb` from a structural model

For larger communities it can be convenient to rely on a structural model.
The structural models implemented are:
`nichemodel(S; C)`, `cascademodel(S; C)`, nestedhierarchymodel(S; C) and
`mpnmodel(S; C, p_forbidden)`.

To generate a food web from one of these models you have to follow this syntax:
`FoodWeb(model_name, model_arguments, optional_FoodWeb_arguments)`.

For instance, to generate a `FoodWeb` of 10 species (`S`) with 15 links (`L`)
and predator-prey body mass ratio (`Z`) of 50 with the niche model, you can do:

```jldoctest
julia> foodweb = FoodWeb(nichemodel, 15; L = 15, Z = 50);

julia> richness(foodweb) == 15
true

julia> foodweb.method == "nichemodel"
true
```

Moreover, while generating the `FoodWeb` we check that it does not have cycles
or disconnected species.
Moreover, while generating the `FoodWeb`,
by default we check that it does not disconnected species,
but we do not check that it does not contain loops.
These behaviours can respectively be changed by setting the keyword arguments
`check_cycle` and  `check_disconnected` to `true` or `false`.

By default, we set a tolerance corresponding to 10% of the number of links
given in argument (`L`), or 10% of the connectance if you give a connectance (`C`).
For instance, if you create a `FoodWeb` with 20 links,
by default we ensure that `FoodWeb` in output will contain between 18 and 22 links.

```jldoctest
julia> foodweb = FoodWeb(nichemodel, 15; L = 15, Z = 50); # by default tol_L = round(0.1*L)

julia> 13 <= n_links(foodweb) <= 18
true
```

However, the default tolerance can be changed with the `tol_L` argument
if you give a number of links (`L`)
or with `tol_C` if you give a connectance (`C`).

```jldoctest
julia> foodweb = FoodWeb(nichemodel, 15; L = 15, Z = 50, tol_L = 0);

julia> n_links(foodweb) == 15
true
```

`FoodWeb`s are generated randomly and can be rejected if they do not satisfy
one of the properties defined above (number of links not in the tolerance range,
cycles, etc.).
Thus we repeat the generation of the `FoodWeb` until all criteria are satisfied
or until the number of maximum iteraction `iter_max` is reached.
If the maximum number of iterations is reached an error is thrown.
That number can be controlled by the `iter_max` keyword argument,
default is set to `1e5`.

# Generate a `FoodWeb` from a `UnipartiteNetwork`

Lastly, EcologicalNetworksDynamics.jl has been designed to interact nicely
with EcologicalNetworks.jl.
Thus you can also create a `FoodWeb` from a `UnipartiteNetwork`:

```jldoctest
julia> uni_net = cascademodel(10, 0.1); # generate a UnipartiteNetwork

julia> foodweb = FoodWeb(uni_net; quiet = true);

julia> foodweb.A == uni_net.edges # same adjacency matrices
true
```

# `FoodWeb` struct

The function returns a `FoodWeb` which is a collection of the following fields:

  - `A` the adjacency matrix
  - `species` the vector of species identities
  - `M` the vector of species body mass
  - `metabolic_class` the vector of species metabolic classes
  - `method` describes which model (e.g. niche model) was used to generate `A`
    if no model has been used `method="unspecified"`

See also [`MultiplexNetwork`](@ref).
"""
function FoodWeb(
    A::AbstractMatrix;
    species::Vector{<:Label} = default_speciesid(A),
    Z::Real = 1,
    M::Vector{<:Real} = compute_mass(A, Z),
    metabolic_class::Vector{<:Label} = default_metabolic_class(A),
    method::String = "unspecified",
    quiet = false,
)
    S = richness(A)
    @check_size_is_richness² A S
    metabolic_class = clean_metabolic_class(metabolic_class, A)
    species = clean_labels(species, S)
    quiet || is_connected(SimpleDiGraph(A)) || @warn disconnected_warning
    FoodWeb(sparse(A), species, M, metabolic_class, method)
end

function FoodWeb(
    model::Function,
    S = nothing;
    C = nothing,
    L = nothing,
    p_forbidden = nothing,
    tol_C = isnothing(C) ? nothing : 0.1 * C,
    tol_L = isnothing(L) ? nothing : round(Integer, 0.1 * L),
    check_cycle = false,
    check_disconnected = true,
    iter_max = 10^5,
    quiet = false,
    Z::Real = 1,
    M::Union{Nothing,AbstractVector} = nothing,
)
    check_structural_model(model)
    if isnothing(L) & isnothing(C)
        throw(ArgumentError("Should provide a connectance `C` or a number of links `L`."))
    elseif !isnothing(L) & !isnothing(C)
        throw(ArgumentError("Cannot provide both a connectance `C` and \
            a number of links `L`. Only one of these two arguments should be given."))
    elseif !isnothing(L)
        isnothing(tol_C) || throw(ArgumentError("You gave a number of links (`L = $L`) and \
        a tolerance on the connectance (`tol_C = $tol_C`). \
        Either provide a connectance (`C`) or \
        use `tol_L` to control the tolerance on the number of links."))
        A = model_foodweb_from_L(
            model,
            S,
            L,
            p_forbidden,
            tol_L,
            check_cycle,
            check_disconnected,
            iter_max,
        )
    elseif !isnothing(C)
        isnothing(tol_L) || throw(ArgumentError("You gave a connectance (`C = $C`) and \
        a tolerance on the on the number of links (`tol_L = $tol_L`). \
        Either provide a number of links (`L`) or \
        use `tol_C` to control the tolerance on the connectance."))
        A = model_foodweb_from_C(
            model,
            S,
            C,
            p_forbidden,
            tol_C,
            check_cycle,
            check_disconnected,
            iter_max,
        )
    end
    (species, M, metabolic_class, method) = structural_foodweb_data(A, M, Z, model)
    quiet || is_connected(SimpleDiGraph(A)) || @warn disconnected_warning
    FoodWeb(A, species, M, metabolic_class, method)
end

const disconnected_warning = "'A' contains disconnected species \
    w.r.t. trophic interactions."

function structural_foodweb_data(A, M, Z, model)
    metabolic_class = default_metabolic_class(A)
    species = default_speciesid(A)
    if isnothing(M)
        M = compute_mass(A, Z)
    end
    method = string(Symbol(model))
    (species, M, metabolic_class, method)
end
#### end ####

#### Type display ####
"""
One line FoodWeb display.
"""
function Base.show(io::IO, foodweb::FoodWeb)
    S = richness(foodweb)
    links = count(foodweb.A)
    print(io, "FoodWeb(S=$S, L=$links)")
end

"""
Multiline FoodWeb display.
"""
function Base.show(io::IO, ::MIME"text/plain", foodweb::FoodWeb)

    # Specify parameters
    S = richness(foodweb)
    links = count(foodweb.A)
    class = foodweb.metabolic_class
    n_p = count(class .== "producer")
    n_i = count(class .== "invertebrate")
    n_v = count(class .== "ectotherm vertebrate")

    # Display output
    println(io, "FoodWeb of $S species:")
    println(io, "  A: sparse matrix with $links links")
    println(io, "  M: " * vector_to_string(foodweb.M))
    println(io, "  metabolic_class: $n_p producers, $n_i invertebrates, $n_v vertebrates")
    println(io, "  method: $(foodweb.method)")
    print(io, "  species: " * vector_to_string(foodweb.species))
end

function vector_to_string(vector)
    length(vector) >= 4 ? long_vector_to_string(vector) : short_vector_to_string(vector)
end

function vector_to_string(vector::T where {T<:SparseVector})
    vector.n >= 4 ? long_vector_to_string(vector) : short_vector_to_string(vector)
end

function short_vector_to_string(short_vector)
    out = "["
    n = length(short_vector)
    n <= 4 || throw(ArgumentError("Vector is too long: should be of length 4 or less."))

    for i in 1:(n-1)
        out *= "$(short_vector[i]), "
    end

    out *= "$(short_vector[end])]"
    out
end

function short_vector_to_string(short_vector::T where {T<:SparseVector})
    out = "["
    n = length(short_vector)
    n <= 4 || throw(ArgumentError("Vector is too long: should be of length 4 or less."))

    for i in 1:(n-1)
        out *= display_spvalue(short_vector[i]) * ", "
    end

    out *= display_spvalue(short_vector[end]) * "]"
    out
end

function long_vector_to_string(long_vector)
    n = length(long_vector)
    n >= 4 || throw(ArgumentError("Vector is too short: should be of length 4 or more."))
    "[$(long_vector[1]), $(long_vector[2]), ..., $(long_vector[end-1]), $(long_vector[end])]"
end

function long_vector_to_string(long_vector::T where {T<:SparseVector})
    n = long_vector.n
    n >= 4 || throw(ArgumentError("Vector is too short: should be of length 4 or more."))
    out₁ = "[$(display_spvalue(long_vector[1])), $(display_spvalue(long_vector[2])), ..., "
    out₂ = "$(display_spvalue(long_vector[end-1])), $(display_spvalue(long_vector[end]))]"
    out₁ * out₂
end

function display_spvalue(value)
    out = value == 0.0 ? "⋅" : "$value"
    out
end
#### end ####

#### Utility functions for generating default values, cleaning some arguments, etc.
"""
Does the user want to replace 'vertebrates' by 'ectotherm vertebrates'?
"""
function replace_vertebrates!(metabolic_class, vertebrates)
    println("Do you want to replace 'vertebrate' by 'ectotherm vertebrate'? (y or n)")
    answer = readline()
    if answer ∈ ["y", "Y", "yes", "Yes", "YES"]
        replace = true
    elseif answer ∈ ["n", "N", "no", "No", "NO"]
        replace = false
    else
        throw(ErrorException("Invalid answer. Please enter yes (y) or no (n)."))
    end
    if replace
        metabolic_class[vertebrates] .= "ectotherm vertebrate"
    end
end

"""
Check that provided metabolic classes are valid.
"""
function clean_metabolic_class(metabolic_class, A)
    # Check that producers are identified as such. If not correct and send a warning.
    prod = producers(A)
    S = richness(A)
    metabolic_class = clean_labels(metabolic_class, S)
    are_producer_valid = all(metabolic_class[prod] .== "producer")
    are_producer_valid ||
        @warn "You provided a metabolic class for basal species: replaced by 'producer'."
    metabolic_class[prod] .= "producer"

    # Replace 'vertebrate' by 'ectotherm vertebrate' if user accepts.
    vertebrates = (1:richness(A))[lowercase.(metabolic_class).=="vertebrate"]
    isempty(vertebrates) || replace_vertebrates!(metabolic_class, vertebrates)

    # Check that metabolic class are valid.
    metabolic_class .= lowercase.(metabolic_class)
    valid_class = ["producer", "ectotherm vertebrate", "invertebrate"]
    are_class_valid = [class ∈ valid_class for class in metabolic_class]
    all(are_class_valid) || throw(
        ArgumentError(
            "An invalid metabolic class has been given, class should be in $valid_class.",
        ),
    )
    metabolic_class
end

"""
Check that labels have the correct format and convert them to `String`s if needed.
"""
function clean_labels(labels, S)
    @check_equal_richness length(labels) S
    all(typeof.(labels) .<: Label) ||
        throw(ArgumentError("Label should be either String or Symbol."))
    String.(labels)
end

compute_mass(A, Z) = Z .^ (trophic_levels(A) .- 1)

default_speciesid(A) = ["s$i" for i in 1:richness(A)]

function default_metabolic_class(A)
    metabolic_class = repeat(["invertebrate"], richness(A))
    metabolic_class[producers(A)] .= "producer"
    metabolic_class
end

"""
Generate a food web of `S` species and connectance `C` from a structural `model`.
Loop until the generated has connectance in [C - ΔC; C + ΔC].
"""
function model_foodweb_from_C(
    model,
    S,
    C,
    p_forbidden,
    ΔC,
    check_cycle,
    check_disconnected,
    iter_max,
)
    C <= 1 || throw(ArgumentError("Connectance `C` should be smaller than 1."))
    if check_disconnected && C < (S - 1) / S^2
        throw(ArgumentError("Connectance `C` should be \
        greater than or equal to (S-1)/S^2 ($((S-1)/S^2) for S=$S) \
        to ensure that there is no disconnected species."))
    end
    ΔC_true = Inf
    is_net_valid = false
    iter = 0
    net = nothing
    while !is_net_valid && (iter <= iter_max)
        net = isnothing(p_forbidden) ? model(S, C) : model(S, C, p_forbidden)
        ΔC_true = abs(connectance(net) - C)
        is_net_valid =
            (ΔC_true <= ΔC) && is_model_net_valid(net, check_cycle, check_disconnected)
        iter += 1
    end
    iter <= iter_max ||
        throw(ErrorException("Could not generate adequate network with C=$C \
        and tol_C=$ΔC before the maximum number of iterations ($iter_max) was reached. \
        Consider either increasing the tolerance on the connectance \
        or, if `check_cycle = true`, to lower the connectance."))
    net
end

function model_foodweb_from_L(
    model,
    S,
    L,
    p_forbidden,
    ΔL,
    check_cycle,
    check_disconnected,
    iter_max,
)
    L >= (S - 1) || throw(ArgumentError("Network should have at least S-1 links \
        to ensure that there is no disconnected species."))
    ΔL_true = Inf
    is_net_valid = false
    iter = 0
    net = nothing
    while !is_net_valid && (iter <= iter_max)
        net = isnothing(p_forbidden) ? model(S, L) : model(S, L, p_forbidden)
        ΔL_true = abs(n_links(net) - L)
        is_net_valid =
            (ΔL_true <= ΔL) && is_model_net_valid(net, check_cycle, check_disconnected)
        iter += 1
    end
    iter <= iter_max ||
        throw(ErrorException("Could not generate adequate network with L=$L \
        and tol_L=$ΔL before the maximum number of iterations ($iter_max) was reached. \
        Consider either increasing the tolerance on the number of links \
        or, if `check_cycle = true` to lower the connectance."))
    net
end

"""
Check that `net` does not contain cycles and does not have disconnected nodes.
"""
function is_model_net_valid(net, check_cycle, check_disconnected)
    graph = SimpleDiGraph(net)
    (!check_cycle || !is_cyclic(graph)) && (!check_disconnected || is_connected(graph))
end

"""
Generate a food web of `S` species and number of links `L` from a structural `model`.
Loop until the generated has a number of links in [L - ΔL; L + ΔL].
If the maximum number of iterations is reached an error is thrown instead.
"""
function model_foodweb(model, S, L::Int64; p_forbidden = nothing, ΔL = 1)
    check_structural_model(model)
    ΔL_true = Inf
    iter, iter_max = 0, 1e5
    net = nothing
    while (ΔL_true > ΔL) && (iter <= iter_max)
        net = isnothing(p_forbidden) ? model(S, L) : model(S, L, p_forbidden)
        ΔL_true = abs(n_links(net) - L)
        iter += 1
    end
    iter <= iter_max ||
        throw(ErrorException("The maximum number of iteration has been reached."))
    net
end

function check_structural_model(model)
    model_name = model |> Symbol |> string
    implemented_models = ["niche_model", "cascade_model"]
    model_name ∈ implemented_models ||
        throw(ArgumentError("Invalid 'model': should be in $implemented_models."))
end
#### end ####

#### Create FoodWeb from an adjacency list ####
function FoodWeb(al; kwargs...)
    # Flags to know if species identities
    # are refered with indexes (Integer) or label (Symbol or String)
    index_style = true
    label_style = true
    if !(eltype(al) <: Pair)
        throw(
            ArgumentError(
                "Invalid adjacency list type: $(typeof(al)). " *
                "Expected a collection of pairs.",
            ),
        )
    end
    pair_vector = []
    for pair in al
        pred, prey, style = parse_pair(pair)
        style == :index ? (label_style = false) : (index_style = false) # update flags
        if sum([label_style, index_style]) != 1
            throw(
                ArgumentError(
                    "Species identity style should be consistent within the pairs. " *
                    "You used two different style: " *
                    "1. index style, species are identified with `Integer`s " *
                    "2. label style, species are identified with `String`s or `Symbol`s " *
                    "(e.g. `:lion`, `:hyena`).",
                ),
            )
        end
        push!(pair_vector, pred => prey)
    end
    if !allunique(first.(pair_vector))
        throw(
            ArgumentError(
                "Duplicated key (predator), key cannot be repeated. " *
                "For instance, if species 1 eats species 2 and 3, " *
                "instead of writing [1 => 2, 1 => 3] " *
                "write [1 => [2, 3]] or [1 => (2, 3)].",
            ),
        )
    end
    pair_dict = Dict(pair_vector)
    al_keys = keys(pair_dict)
    al_vals = collect(values(pair_dict))
    al_vals_flatten = collect(Iterators.flatten(al_vals)) # [[1], [2, 3]] -> [1, 2, 3]
    sp_set = union(al_keys, al_vals_flatten)
    sp_sorted = sort([sp for sp in sp_set])
    sp_dict = Dict([id => new_id for (new_id, id) in enumerate(sp_sorted)])
    mapping = name -> sp_dict[name]
    S = length(sp_set)
    A = spzeros(Integer, S, S)
    for (pred, prey_vec) in pair_dict
        for prey in prey_vec
            A[mapping(pred), mapping(prey)] = 1
        end
    end

    # Automatically adjust species labels if needed.
    kwargs = Dict{Symbol,Any}(kwargs)
    if label_style
        if :species in keys(kwargs)
            throw(ArgumentError("Species names are automatically set from labels \
                             in adjacency list. No need to provide `species` argument."))
        else
            kwargs[:species] = sp_sorted
        end
    end
    if index_style && :species ∉ keys(kwargs)
        kwargs[:species] = default_speciesid(A)
    end

    FoodWeb(A; kwargs...)
end

"""
Parse pairs within `FoodWeb()` method working on adjacency list.
"""
function parse_pair(pair)
    pred, prey = pair
    if !(typeof(pred) <: Union{Integer,String,Symbol})
        throw(
            ArgumentError(
                "The first element of the pair, or the key of your dictionary, " *
                "should not be an iterable: either a single Integer, String or Symbol.",
            ),
        )
    end
    if typeof(pred) <: Integer && all(typeof.(prey) .<: Integer)
        return (pred, prey, :index)
    elseif typeof(pred) <: Label && all(typeof.(prey) .<: Label)
        parsed_prey = typeof(prey) <: Label ? [Symbol(prey)] : Symbol.(prey)
        return (Symbol(pred), parsed_prey, :label)
    else
        throw(
            ArgumentError(
                "The elements of your pair should be either all <: Integer " *
                "or all :<Union{String, Symbol}.",
            ),
        )
    end
end
####

abstract type ProducerGrowth end

"""
`LogisticGrowth` constructor.

# Fields

  - `a`: producer competition matrix
  - `K`: vector of producer carrying capacities

See also [`NutrientIntake`](@ref).
"""
mutable struct LogisticGrowth <: ProducerGrowth
    a::AbstractMatrix{Float64}
    K::Vector{Union{Nothing,Float64}}
    LogisticGrowth(a, K) = new(a, K)
end

mutable struct NutrientIntake <: ProducerGrowth
    # FROM THE FUTURE - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # Both nutrients nodes and nutrients-related edges are stored here,
    # so make fields optional and fill them up as corresponding components are added.
    turnover::Option{Vector{Float64}}
    supply::Option{Vector{Float64}}
    concentration::Option{Matrix{Float64}}
    half_saturation::Option{Matrix{Union{Nothing,Float64}}}
    # Name nutrients just like species.
    names::Vector{Symbol} # (just to recall original order)
    index::Dict{Symbol,Int64}
    NutrientIntake(args...) = new(args...)
end

Base.:(==)(a::U, b::V) where {U<:ProducerGrowth,V<:ProducerGrowth} =
    U == V && equal_fields(a, b)

"""
    length(n::NutrientIntake)

Number of nutrients in the `n`utrient intake model.
"""
Base.length(n::NutrientIntake) = length(n.turnover)

"""
One line display FunctionalResponse
"""
Base.show(io::IO, model::ProducerGrowth) = show(io, typeof(model))

"""
Multiline LogisticGrowth display.
"""
function Base.show(io::IO, ::MIME"text/plain", model::LogisticGrowth)
    S = size(model.a, 1)
    println(io, "LogisticGrowth:")
    println(io, "  K - carrying capacity: " * vector_to_string(model.K))
    print(io, "  a - competition: ($S, $S) matrix")
end

"""
Multiline NutrientIntake display.
"""
function Base.show(io::IO, ::MIME"text/plain", model::NutrientIntake)
    n_nutrients = length(model)
    n_producers = size(model.supply, 1)
    println(io, "NutrientIntake - $n_nutrients nutrients:")
    println(io, "  `turnover` rate: $(model.turnover)")
    println(io, "  `supply` concentrations: " * vector_to_string(model.supply))
    println(io, "  relative `concentration`: ($n_producers, $n_nutrients) matrix")
    print(io, "  `half_saturation` densities: ($n_producers, $n_nutrients) matrix")
end

"""
    LogisticGrowth(
        network::EcologicalNetwork;
        a = nothing,
        K = 1,
    )

Create the parameters for the logistic producer growth model.
In the end, the `LogisticGrowth` struct created stores a vector of carrying capacities `K`
and a competition matrix between the producers `a`.

The carrying capacities can be specified via the `K` arguments,
by default they are all set to 1 for the producers and to `nothing` for the consumers.

By default the competition matrix `a` is assumed to have diagonal elements equal to 1
and 0 for all off-diagonal elements.
This default can be changed via the `a` argument.
You can either directly pass the interaction matrix,
a single `Number` that will be interpreted as the value of all diagonal elements,
a tuple of `Number` the first will be interpreted as the diagonal value and
the second as the off-diagonal values, or a named tuple of `Number`.
For the latter, the following aliases can be used to refer to the diagonal elements
'diagonal', 'diag', 'd', and for the off-diagonal elements 'offdiagonal', 'offdiag',
'o', 'rest', 'nondiagonal', 'nond'.

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0]) # 1 & 2 producers and 3 consumer.
       g = LogisticGrowth(foodweb)
       g.a == [
           1 0 0
           0 1 0
           0 0 0
       ]
true

julia> g.K == [1, 1, nothing]
true

julia> K_cst = 5.0
       g = LogisticGrowth(foodweb; K = K_cst) # Change the default K.
       g.K == [K_cst, K_cst, nothing]
true

julia> K_vec = [1, 2, nothing]
       g = LogisticGrowth(foodweb; K = K_vec) # Can also provide a vector.
       g.K == K_vec
true

julia> g = LogisticGrowth(foodweb; a = (diag = 0.5, offdiag = 1.0))
       g.a == [
           0.5 1.0 0.0
           1.0 0.5 0.0
           0.0 0.0 0.0
       ]
true

julia> my_competition_matrix = [
           0.5 1.0 0.0
           1.0 0.5 0.0
           0.0 0.0 0.0
       ]
       g = LogisticGrowth(foodweb; a = my_competition_matrix)
       g.a == my_competition_matrix
true
```

See also [`ModelParameters`](@ref) and [`NutrientIntake`](@ref).
"""
function LogisticGrowth(network::EcologicalNetwork; a = nothing, K = 1)
    S = richness(network)
    isa(K, AbstractVector) || (K = [isproducer(i, network) ? K : nothing for i in 1:S])
    @check_equal_richness length(K) S
    err(mess) = throw(ArgumentError(mess))

    # Construct matrix from user input.
    # Initialize these variables from the argument `a`.
    diag, offdiag, raw = nothing, nothing, nothing
    if isnothing(a)
        diag, offdiag = 1.0, 0.0 # Default.
    elseif a isa Number
        diag, offdiag = a, 0.0
    elseif a isa AbstractMatrix #  Raw matrix provided.
        @assert size(a) == (S, S)
        raw = a
    elseif a isa Tuple && eltype(a) <: Real && length(a) in [1, 2]
        n = length(a)
        if n == 1
            diag, offdiag = a[1], 0.0
        elseif n == 2
            diag, offdiag = a
        end
    elseif a isa NamedTuple && eltype(a) <: Real && length(a) in [1, 2]
        diag_aliases = [:diag, :diagonal, :d] # For convenience.
        for key in diag_aliases
            if haskey(a, key)
                if !isnothing(diag)
                    err("Ambiguous names in provided tuple: $(keys(a)). \
                         Which one refers to the diagonal value?")
                end
                diag = a[key]
            end
        end
        offdiag_aliases = [:offdiagonal, :offdiag, :o, :rest, :nondiagonal, :nd]
        for key in offdiag_aliases
            if haskey(a, key)
                if !isnothing(offdiag)
                    err("Ambiguous names in provided tuple: $(keys(a)). \
                         Which one refers to the non-diagonal values?")
                end
                offdiag = a[key]
            end
        end
        if isnothing(diag) || isnothing(offdiag)
            err("Wrong name in provided named tuple names $(keys(a)). \
                 The valid names to specify the diagonal elements of the `a` matrix are \
                 $diag_aliases and for the off-diagonal elements $offdiag_aliases.")
        end
    else
        err("Invalid matrix argument: $(a) of type $(typeof(a)).")
    end

    # The potential information to build the competition matrix has been processed.
    # Build the matrix or read it from the raw input.
    if isnothing(raw)
        prods = producers(network)
        # If the offdiagonal elements are null (nothing or zero), then the matrix
        # has mostly null entries, in which case a sparse matrix is used.
        a = (isnothing(offdiag) || offdiag == 0) ? spzeros(S, S) : zeros(S, S)
        for i in prods, j in prods
            a[i, j] = i == j ? diag : offdiag
        end
    else
        @assert size(raw) == (S, S)
        a = sparse(raw)
    end

    # Competition between producers can only occur between a pair of producers.
    non_producer = filter(!isproducer, network)
    if !isempty(non_producer)
        @assert all(a[non_producer, :] .== 0)
        @assert all(a[:, non_producer] .== 0)
    end
    LogisticGrowth(a, K)
end

"""
    NutrientIntake(
        network::EcologicalNetwork;
        n_nutrients = 2,
        turnover = 0.25,
        supply = fill(10.0, n_nutrients),
        concentration = collect(LinRange(1, 0.5, n_nutrients)),
        half_saturation = 1.0,
    )

Create parameters for the nutrient intake model of producer growths.
These parameters are:

  - the nutrient `turnover` rate (vector of length `n_nutrients`)
  - the `supply` concentration for each nutrient (vector of length `n_nutrients`)
  - the relative `concentration` of each nutrients in each producers
    (matrix of size (n_producers, n_nutrients))
  - the `half_saturation` densities for each nutrient-producer pair
    (matrix of size (n_producers, n_nutrients))

# Examples

```jldoctest
julia> foodweb = FoodWeb([4 => [1, 2, 3]]); # 4 feeds on 1, 2 and 3.
       ni = NutrientIntake(foodweb) # knights who say..
       length(ni) # 2 nutrients by default.
2

julia> ni.turnover == [0.25, 0.25]
true

julia> ni.supply == [10, 10]
true

julia> ni.concentration == [1 0.5; 1 0.5; 1 0.5]
true

julia> ni.half_saturation == [1 1; 1 1; 1 1]
true

julia> ni = NutrientIntake(foodweb; turnover = 1.0)
       ni.turnover == [1.0, 1.0]
true

julia> ni = NutrientIntake(foodweb; n_nutrients = 5)
       length(ni)
5
```

See also [`ModelParameters`](@ref) and [`ProducerGrowth`](@ref).
"""
function NutrientIntake(
    network::EcologicalNetwork;
    n_nutrients = 2,
    turnover = 0.25,
    supply = fill(10.0, n_nutrients),
    concentration = collect(LinRange(1, 0.5, n_nutrients)),
    half_saturation = 1.0,
)
    0 < turnover <= 1 || throw(ArgumentError("`turnover` rate should be in ]0, 1], \
                                              not $turnover."))

    length(supply) == 1 && (supply = fill(supply[1], n_nutrients))
    length(supply) == n_nutrients || throw(
        ArgumentError("`supply` should be of length 1 or `n_nutrients` = $n_nutrients."),
    )

    n_producers = length(producers(network))
    c = size(concentration)
    if c == () || c == (1,)
        concentration = fill(concentration[1], n_producers, n_nutrients)
    elseif c == (n_nutrients,)
        concentration = repeat(concentration, 1, n_producers)'
    elseif c != (n_producers, n_nutrients)
        throw(ArgumentError("`concentration` should be either: a number, \
                            a vector of length 1 or number of producers = $n_producers, \
                            or a matrix of size \
                            (number of producer = $n_producers, \
                            number of nutrients = $n_nutrients) \
                            not $concentration (of type $(typeof(concentration)))."))
    end

    length(turnover) == 1 && (turnover = fill(turnover[1], n_nutrients))
    length(turnover) != n_nutrients &&
        throw(ArgumentError("`turnover` should either be a number, a vector of length 1 \
                             or a vector of length `n_nutrients` = $n_nutrients \
                             not $turnover (of type $(typeof(turnover)))."))

    h = size(half_saturation)
    if h == () || h == (1,)
        half_saturation = fill(half_saturation[1], n_producers, n_nutrients)
    elseif h == (n_producers,)
        half_saturation = repeat(half_saturation, 1, n_nutrients)
    elseif h != (n_producers, n_nutrients)
        throw(
            ArgumentError("`half_saturation` should be either: a number, \
                            a vector of length 1 or number of producers = $n_producers, \
                            or a matrix of size \
                            (number of producer = $n_producers, \
                            number of nutrients = $n_nutrients) \
                            not $half_saturation (of type $(typeof(half_saturation))."),
        )
    end

    NutrientIntake(turnover, supply, concentration, half_saturation, [], Dict())
end

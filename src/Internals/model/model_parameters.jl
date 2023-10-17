#=
Model parameters
=#

#### Type definition ####
mutable struct ModelParameters
    # FROM THE FUTURE - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # These already have some "empty semantics": no need to Option-ize them.
    environment::Environment # (almost nothing left in there)
    temperature_response::TemperatureResponse # (NoTemperatureResponse is like 'nothing')
    # These don't exactly have an 'empty' variant.
    network::Option{EcologicalNetwork}
    biorates::BioRates # (this one does but all values are initially 'nothing' inside)
    _topology::Topology # This will actually be part of the future refactoring.
    functional_response::Option{FunctionalResponse}
    producer_growth::Option{ProducerGrowth}
    # Since 'foodweb' is still a mandatory input to construct interaction layers,
    # keep this artificial reference to it to make the system/components API work
    # until we refactor all the internals.
    _foodweb::Option{FoodWeb}
    # From the future: store nodes/edges values in this scratch space
    # before we actually know which functional response / producer growth type
    # will be required. `Biorates` is currently a legacy extension to the "scratch".
    # *Alias* the values from the scratch space
    # when eventually distributing them to `functional_response` or `producer_growth`.
    _scratch::Dict{Symbol,Any}
    # From the future: use this cache to store data held
    # by the various views handled to users.
    # Keys into the cache are the corresponding
    # standard (=first, not aliases) property paths,
    # that the framework ensures to be unique.
    # All data within the cache is *redundant* with the rest of the model,
    # so it could in principle be safely deleted.
    _cache::Dict{Union{Symbol,Expr},Any}
    # Empty version for the system.
    function ModelParameters()
        ModelParameters(
            Environment(),
            NoTemperatureResponse(),
            nothing,
            BioRates(),
            Topology(),
            repeat([nothing], 3)...,
            Dict(),
            Dict(),
        )
    end
    ModelParameters(args...) = new(args...)
end
# Required to fork the system.
# Self-references (very) fortunately are not a problem:
# https://discourse.julialang.org/t/how-is-deepcopy-so-clever-regarding-aliasing-and-self-reference/113235
Base.copy(m::ModelParameters) = deepcopy(m)
#### end ####

# Ignore cached values for equivalence relation.
const model_equivalence_ignored_fields = Set([:_cache])
Base.:(==)(a::ModelParameters, b::ModelParameters) =
    equal_fields(a, b; ignore = model_equivalence_ignored_fields)

#### Type display ####
"""
One line ModelParameters display.
"""
function Base.show(io::IO, params::ModelParameters)
    response_type = nameof(typeof(params.functional_response))
    print(io, "ModelParameters{$response_type}")
    !get(io, :compact, false) && print(io, "(", params.network, ")")
end

"""
Multiline ModelParameters display.
"""
function Base.show(io::IO, ::MIME"text/plain", params::ModelParameters)

    # Display output
    nm(x) = nameof(typeof(x))
    response_type = nm(params.functional_response)
    pgrowth_model = nm(params.producer_growth)
    println(io, "ModelParameters{$response_type, $pgrowth_model}:")
    println(io, "  network: ", params.network)
    println(io, "  environment: ", params.environment)
    println(io, "  biorates: ", params.biorates)
    println(io, "  functional_response: ", nm(params.functional_response))
    println(io, "  producer_growth: ", nm(params.producer_growth))
    println(io, "  temperature_response: ", nm(params.temperature_response))
end
#### end ####

"""
    ModelParameters(
        network::EcologicalNetwork;
        biorates::BioRates=BioRates(foodweb),
        environment::Environment=Environment(foodweb),
        functional_response::FunctionalResponse=BioenergeticResponse(foodweb),
        producer_growth::ProducerGrowth=ProducerGrowth(foodweb),
        temperature_response::TemperatureResponse
    )

Generate the parameters of the species community.

Default values are taken from
[Brose et al., 2006](https://doi.org/10.1890/0012-9658(2006)87%5B2411:CBRINF%5D2.0.CO%3B2).
The parameters are compartmented in different groups:

  - [`FoodWeb`](@ref): foodweb information (e.g. adjacency matrix)
  - [`BioRates`](@ref): biological species rates (e.g. growth rates)
  - [`Environment`](@ref): environmental variables (e.g. carrying capacities)
  - [`FunctionalResponse`](@ref) (F): functional response form
    (e.g. classic or bioenergetic functional response)
  - [`ProducerGrowth`](@ref): model for producer growth (e.g. logistic or nutrient intake)
  - [`TemperatureResponse`](@ref): method used for temperature dependency

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 1; 0 0])
       p = ModelParameters(foodweb)
ModelParameters{BioenergeticResponse, LogisticGrowth}:
  network: FoodWeb(S=2, L=1)
  environment: Environment(T=293.15K)
  biorates: BioRates(d, r, x, y, e)
  functional_response: BioenergeticResponse
  producer_growth: LogisticGrowth
  temperature_response: NoTemperatureResponse

julia> p.network # Check that stored foodweb is the same as the one we provided.
FoodWeb of 2 species:
  A: sparse matrix with 1 links
  M: [1.0, 1.0]
  metabolic_class: 1 producers, 1 invertebrates, 0 vertebrates
  method: unspecified
  species: [s1, s2]

julia> p.functional_response # Default is bioenergetic.
BioenergeticResponse:
  B0: [0.5, 0.5]
  c: [0.0, 0.0]
  h: 2.0
  ω: (2, 2) sparse matrix

julia> classic_response = ClassicResponse(foodweb)
       p = ModelParameters(foodweb; functional_response = classic_response);
       p.functional_response # Check that the functional response is now "classic".
ClassicResponse:
  c: [0.0, 0.0]
  h: 2.0
  ω: (2, 2) sparse matrix
  hₜ: (2, 2) sparse matrix
  aᵣ: (2, 2) sparse matrix
```

[`ModelParameters`](@ref) can also be generated from a [`MultiplexNetwork`](@ref).

```jldoctest
julia> foodweb = FoodWeb([0 1; 0 0])
       net = MultiplexNetwork(foodweb)
       p = ModelParameters(net; functional_response = ClassicResponse(net))
ModelParameters{ClassicResponse, LogisticGrowth}:
  network: MultiplexNetwork(S=2, Lt=1, Lc=0, Lf=0, Li=0, Lr=0)
  environment: Environment(T=293.15K)
  biorates: BioRates(d, r, x, y, e)
  functional_response: ClassicResponse
  producer_growth: LogisticGrowth
  temperature_response: NoTemperatureResponse
```
"""
function ModelParameters(
    network::EcologicalNetwork;
    biorates::BioRates = BioRates(network),
    environment::Environment = Environment(),
    functional_response::FunctionalResponse = BioenergeticResponse(network),
    producer_growth::ProducerGrowth = LogisticGrowth(network),
    temperature_response::TemperatureResponse = NoTemperatureResponse(),
)
    if isa(network, MultiplexNetwork) && !(isa(functional_response, ClassicResponse))
        type_response = typeof(functional_response)
        @warn "Non-trophic interactions for `$type_response` are not supported. \
               Use a classical functional response instead: `$ClassicResponse`."
    end
    ModelParameters(
        environment,
        temperature_response,
        network,
        biorates,
        Topology(),
        functional_response,
        producer_growth,
        nothing,
        Dict(),
        Dict(),
    )
end

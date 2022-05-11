#=
Model parameters
=#

#### Type definition ####
mutable struct ModelParameters{R<:FunctionalResponse}
    foodweb::FoodWeb
    biorates::BioRates
    environment::Environment
    functional_response::R
end
#### end ####

#### Type display ####
"One line ModelParameters display."
function Base.show(io::IO, params::ModelParameters)
    response_type = typeof(params.functional_response)
    print(io, "ModelParameters{$response_type}")
    !get(io, :compact, false) && print(io, "(", params.foodweb, ")")
end

"Multiline ModelParameters display."
function Base.show(io::IO, ::MIME"text/plain", params::ModelParameters)

    # Display output
    response_type = typeof(params.functional_response)
    println(io, "ModelParameters{$response_type}:")
    println(io, "  foodweb: ", params.foodweb)
    println(io, "  environment: ", params.environment)
    println(io, "  biorates: ", params.biorates)
    print(io, "  functional_response: ", params.functional_response)
end
#### end ####

"""
    ModelParameters(
        FoodWeb::FoodWeb;
        BioRates::BioRates=BioRates(foodweb),
        Environment::Environment=Environment(foodweb),
        F::FunctionalResponse=BioenergeticResponse(foodweb)
    )

Generate the parameters of the species community.

Default values are taken from
[Brose et al., 2006](https://doi.org/10.1890/0012-9658(2006)87[2411:CBRINF]2.0.CO;2).
The parameters are compartimented in different groups:
- [`FoodWeb`](@ref): foodweb information (e.g. adjacency matrix)
- [`BioRates`](@ref): biological species rates (e.g. growth rates)
- [`Environment`](@ref): environmental variables (e.g. carrying capacities)
- [`FunctionalResponse`](@ref) (F): functional response form
    (e.g. classic or bioenergetic functional response)

# Examples
```jldoctest
julia> foodweb = FoodWeb([0 1; 0 0]); # create a simple foodweb

julia> p = ModelParameters(foodweb) # default
ModelParameters{BioenergeticResponse}:
  foodweb: FoodWeb(S=2, L=1)
  environment: Environment(K=[nothing, 1], T=293.15K)
  biorates: BioRates(e, r, x, y)
  functional_response: BioenergeticResponse

julia> p.foodweb # check that stored foodweb is the same than the one we provided
FoodWeb of 2 species:
  A: sparse matrix with 1 links
  M: [1.0, 1.0]
  metabolic_class: 1 producers, 1 invertebrates, 0 vertebrates
  method: unspecified
  species: [s1, s2]

julia> p.functional_response # default is bionergetic
BioenergeticResponse:
  B0: [0.5, 0.5]
  c: [0.0, 0.0]
  h: 2.0
  ω: 2x2 sparse matrix

julia> classic_response = ClassicResponse(foodweb); # choose classic functional response

julia> p = ModelParameters(foodweb, functional_response = classic_response);

julia> p.functional_response # check that the functional response is now "classic"
ClassicResponse:
  c: [0.0, 0.0]
  h: 2.0
  ω: 2x2 sparse matrix
  hₜ: 2x2 sparse matrix
  aᵣ: 2x2 sparse matrix
```
"""
function ModelParameters(
    foodweb::FoodWeb;
    biorates::BioRates=BioRates(foodweb),
    environment::Environment=Environment(foodweb),
    functional_response::FunctionalResponse=BioenergeticResponse(foodweb)
)

    ModelParameters(foodweb, biorates, environment, functional_response)
end

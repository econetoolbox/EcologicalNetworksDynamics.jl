include("multiplex_identifiers.jl")

# Construct several layers at once using the "2D" multiplex API.
nti_components = InteractionDict(
    :trophic => TrophicLayer,
    :competition => Competition.Layer,
    :facilitation => Facilitation.Layer,
    :interference => Interference.Layer,
    :refuge => Refuge.Layer,
)

# Construct a sequence of blueprints from 2D kwargs.
function nontrophic_layers(input)
    args = parse_multiplex_arguments(input)
    # Only layers with at least 1 parameter specified get reified into a blueprint.
    blueprints = InteractionDict()
    for (int, NtiLayer) in nti_components
        sub = args[int]
        if !isempty(sub)
            sub = MultiplexParametersDict{Any}(sub)
            blueprints[int] = NtiLayer(sub)
        end
    end
    blueprints
end
nontrophic_layers(; kwargs...) = nontrophic_layers(kwargs)
export nontrophic_layers

# Output a blueprint sum for consistency as arguments to default_model.
NontrophicLayers(; kwargs...) =
    sum(values(nontrophic_layers(kwargs)); init = BlueprintSum())
export NontrophicLayers

add_nontrophic_layers!(m::Model, input) = add!(m, values(nontrophic_layers(input))...)
add_nontrophic_layers!(m::Model; kwargs...) = add_nontrophic_layers!(m, kwargs)
export add_nontrophic_layers!

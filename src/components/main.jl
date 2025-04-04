# Since we haven't refactored the internals yet,
# the components described here are just a raw embedding of the former 'Internal' interface,
# nicknamed 'raw' in components code.
# Take this opportunity to pick stable names and encapsulate the whole 'Internals' module,
# so we can refactor it later, *deeply*,
# hopefully without needing to change any exposed component/method.

# Mostly, separate "data" components (typically, biorates)
# from "functional" components (typically functional responses):
# data components bring data to the model,
# while functional components specify the behaviour of the model
# based on the data they depend on.
# TODO: reify these two sorts of components?
#       In the end: data requires behaviour and other data to be *built*,
#       so it's a blueprint expansion requirement,
#       but behaviour requires data to be *ran*, so it's a true component requirement?

# To best understand subsequent code,
# and until proper documentation is written,
# I would advise that the following files be skimmed in order
# as later comments build upon earlier ones.

# TODO there is heavy replication going on in components specification,
# and boilerplate that could be greatly reduced
# once the legacy internals have refactored and simplified.
# Maybe only a few archetypes components are needed:
#   - Graph data.
#   - Nodes.
#   - Dense nodes data.
#   - Sparse (templated) nodes data.
#   - Edges.
#   - Dense edges data.
#   - Sparse (templated) edges data.
#   - Behaviour (graph data that actually represents *code* to run the model).

# Helpers.
include("./macros_keywords.jl")
include("./allometry.jl")
include("./values_check.jl")
include("./display.jl")
# Behaviour blueprints typically "optionally bring" other blueprints.
# This utils factorizes how args/kwargs are passed from its inner constructor
# to each of its fields.
include("./args_to_fields.jl")

# Central in the model nodes.
include("./species.jl")

# Trophic links, structuring the whole network.
# (typical example 'edge' data)
include("./foodweb.jl")

#  # Biorates and other values parametrizing the ODE.
#  # (typical example 'nodes' data)
include("./body_mass.jl")
include("./metabolic_class.jl")

# Useful global values to calculate other biorates.
# (typical example 'graph' data)
include("./temperature.jl")

# Replicated/adapted from the above.
# TODO: factorize subsequent repetitions there.
# Easier once the Internals become more consistent?
include("./hill_exponent.jl") # <- First, good example of 'graph' component. Read first.
include("./growth_rate.jl") # <- First, good example of 'node' component. Read first.
include("./efficiency.jl") # <- First, good example of 'edges' component. Read first.
include("./carrying_capacity.jl")
include("./mortality.jl")
include("./metabolism.jl")
include("./maximum_consumption.jl")
include("./producers_competition.jl")
include("./consumers_preferences.jl")
include("./handling_time.jl")
include("./attack_rate.jl")
include("./half_saturation_density.jl")
include("./intraspecific_interference.jl")
include("./consumption_rate.jl")

# Namespace nutrients data.
include("./nutrients/main.jl")
export Nutrients

include("./nontrophic_layers/main.jl")
using .NontrophicInteractions
const Nti = NontrophicInteractions
export NontrophicInteractions, Nti
export Competition
export Facilitation
export Interference
export Refuge

# The above components mostly setup *data* within the model.
# In the next they mostly specify the *code* needed to simulate it.
include("./producer_growth.jl")
include("./functional_responses.jl")
# Metabolism and Mortality are also technically code components,
# but they are not reified yet and only reduce
# to the single data component they each bring.

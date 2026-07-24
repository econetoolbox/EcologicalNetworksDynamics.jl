# Consume `NetworkFramework` to specify the components handed out to end users.

# Mostly, separate "data" components (typically, biorates)
# from "functional" components (typically functional responses):
# data components bring data to the model (≈ fields in `Network`),
# while functional components specify the behaviour of the model (≈ code in `Differentials`)
# based on the data they depend on.
# TODO: reify these two sorts of components in `NetworkFramework`?
#       In the end: data requires behaviour and other data to be *built*,
#       so it's a blueprint expansion requirement,
#       but behaviour requires data to be *ran*, so it's a true component requirement?

# To best understand subsequent code,
# and until proper documentation is written,
# I would advise that the following files be read in order
# as later comments build upon earlier ones.

# (skip on first read: defining typical allometry-related blueprints)
include("./allometry.jl")

# First example of a nodes class.
include("./species.jl")

# First example of an edges web.
#  include("./foodweb.jl")

# First example of nodes data.
#  include("./body_mass.jl")

# Non-numeric nodes data, that require checking against model values.
#  include("./metabolic_class.jl")

# First example graph-level data.
#  include("./temperature.jl")

# Nodes data only relevant to a sub-class.
#  include("./growth_rate.jl")

# Graph-level data.
#  include("./hill_exponent.jl")

# Edge-level data.
#  include("./efficiency.jl")

# XXX: On hold beyond this line, reintroduce as needed after internals refactoring.
# ==========================================================================================
# Helpers.
#  include("./macros_keywords.jl")
#  include("./shared.jl")

# Behaviour blueprints typically "optionally bring" other blueprints.
# This utils factorizes how args/kwargs are passed from its inner constructor
# to each of its fields.
#  include("./args_to_fields.jl")

#  # Replicated/adapted from the above.
#  # TODO: factorize subsequent repetitions there.
#  # Easier once the Internals become more consistent?
#  include("./carrying_capacity.jl")
#  include("./mortality.jl")
#  include("./metabolism.jl")
#  include("./maximum_consumption.jl")
#  include("./producers_competition.jl")
#  include("./consumers_preferences.jl")
#  include("./handling_time.jl")
#  include("./attack_rate.jl")
#  include("./half_saturation_density.jl")
#  include("./intraspecific_interference.jl")
#  include("./consumption_rate.jl")

#  # Namespace nutrients data.
#  include("./nutrients/main.jl")
#  export Nutrients

#  include("./nontrophic_layers/main.jl")
#  using .NontrophicInteractions
#  const Nti = NontrophicInteractions
#  export NontrophicInteractions, Nti
#  export Competition
#  export Facilitation
#  export Interference
#  export Refuge

#  # The above components mostly setup *data* within the model.
#  # In the next they mostly specify the *code* needed to simulate it.
#  include("./producer_growth.jl")
#  include("./functional_responses.jl")
#  # Metabolism and Mortality are also technically code components,
#  # but they are not reified yet and only reduce
#  # to the single data component they each bring.

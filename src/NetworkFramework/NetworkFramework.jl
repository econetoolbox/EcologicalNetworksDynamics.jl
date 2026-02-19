"""
The library dedicated to component authors.

It exposes functionalities of the system/blueprint/components framework,
yet in the specific context of writing components for values of type `Network`.

In other words, typical components in the package are expected to be:
- Component bringing a class.
- Component bringing a web.
- Component bringing network-level data.
- Component bringing node-level data.
- Component bringing edge-level data.

.. each with their own typical set of blueprints, properties,
input checking/parsing, semantics.
This module aims to make it easy for component authors to do that.
"""
module NetworkFramework

import EcologicalNetworksDynamics: EN, N, F, I, argerr

using Crayons

# Define extension points to customize components behaviours.
include("dispatchers.jl")
using .Dispatchers

# Typical user input data preprocessing.
include("./Inputs/Inputs.jl") # HERE: into hard-refreshing the whole module.

# Dedicate framework to the specific `Network` value.
include("framework.jl")

# Typical views into network data.
include("./Views/Views.jl")

# Templates for typical network components.
include("./class.jl")
include("./web.jl")
include("./nodes.jl")

end

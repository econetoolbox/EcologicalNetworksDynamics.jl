module Interface

# XXX: translate or clear previous tests under onhold/ folder.

# Testing order matters, in the sense that laters tests *cannot* pass if the former fail.

include("./symbols.jl")

# Input checking.
include("./convert.jl")
include("./lists.jl")

# Typical network compartments.
include("graph_field.jl")
include("class.jl")
include("web.jl")
include("subclass.jl")
include("node_field.jl")
include("allometric_node_field.jl")
include("allometric_edge_field.jl")
include("edge_field.jl")
include("kwargs.jl")

# Components particularities, not already tested by the above.
include("data_components/temperature.jl")      #
include("data_components/species.jl")          #
include("data_components/foodweb.jl")          # Run these first
include("data_components/body_mass.jl")        # because they were examples in the above.
include("data_components/metabolic_class.jl")  #
include("data_components/growth_rate.jl")      #
include("data_components/efficiency.jl")       #

include("data_components/carrying_capacity.jl")
include("data_components/hill_exponent.jl")
include("data_components/maximum_consumption.jl")
include("data_components/metabolism.jl")
include("data_components/mortality.jl")
include("data_components/producer_competition.jl")
include("data_components/consumer_preference.jl")
include("data_components/handling_time.jl")
include("data_components/attack_rate.jl")

end

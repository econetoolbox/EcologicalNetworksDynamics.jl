using Crayons
bold = crayon"bold"
blue = crayon"blue"
reset = crayon"reset"
sep(mess) = println("$blue$bold== $mess $(repeat("=", 80 - 4 - length(mess)))$reset")

# Testing utils.
include("./test_failures.jl")
include("./dedicated_test_failures.jl")

# The whole testing suite has been moved to "internals"
# while we are focusing on constructing the library API.
sep("Test internals.")
include("./internals/runtests.jl")

sep("Test System/Blueprints/Components framework.")
include("./framework/runtests.jl")

sep("Test API utils.")
include("./topologies.jl")
include("./aliasing_dicts.jl")
include("./multiplex_api.jl")
include("./graph_data_inputs/runtests.jl")

sep("Test user-facing behaviour.")
include("./user/runtests.jl")

sep("Run doctests (DEACTIVATED while migrating api from 'Internals').")
#  include("./doctests.jl")

sep("Check source code formatting.")
include("./formatting.jl")

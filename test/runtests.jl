# Pick correct test environment.
regular = if ["pinned"] == ARGS
    include("../compat/to_pinned.jl")
    false
elseif ["lower"] == ARGS
    include("../compat/to_lower.jl")
    false
elseif ["latest"] == ARGS || isempty(ARGS)
    # Regular testing with latest compatible versions.
    true
else
    error("Invalid test arguments: $ARGS")
end

import CompatHelperLocal
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

sep("Test user interface.")
include("./user/runtests.jl")

sep("Test against theoretical expectations.")
include("./exp/1nutrient1producer.jl")

sep("Run doctests (DEACTIVATED while migrating api from 'Internals').")
#  include("./doctests.jl")

if regular
    sep("Check source code formatting.")
    include("./formatting.jl")

    sep("Check compatibility entries.")
    CompatHelperLocal.@check()
end

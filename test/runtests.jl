# Pick correct test environment.
if ["pinned"] == ARGS
    include("../compat/to_pinned.jl")
elseif ["lower"] == ARGS
    include("../compat/to_lower.jl")
elseif ["latest"] == ARGS || isempty(ARGS)
    # Regular testing with latest compatible versions.
else
    error("Invalid test arguments: $ARGS")
end

import CompatHelperLocal

# Testing utils.
include("./utils.jl")
include("./test_failures.jl")
include("./dedicated_test_failures.jl")
using .TestUtils
using .TestFailures

#  sep("Test internal model representation.")
#  include("./networks/runtests.jl")

sep("Test System/Blueprints/Components framework.")
include("./framework/runtests.jl")

#= Silent all this during internals refactoring.

# The whole testing suite has been moved to "internals"
# while we are focusing on constructing the library API.
sep("Test internals.")
include("./internals/runtests.jl")

sep("Test API utils.")
include("./topologies.jl")
include("./aliasing_dicts.jl")
include("./multiplex_api.jl")
include("./graph_data_inputs/runtests.jl")

sep("Test user-facing behaviour.")
include("./user/runtests.jl")

sep("Run doctests (DEACTIVATED while migrating api from 'Internals').")
#  include("./doctests.jl")
=#

sep("Check source code formatting.")
include("./formatting.jl")

sep("Check compatibility entries.")
CompatHelperLocal.@check()

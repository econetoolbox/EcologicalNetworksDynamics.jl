# Pick correct test environment.
if ["pinned"] == ARGS
    include("../compat/to_pinned.jl")
elseif ["lower"] == ARGS
    include("../compat/to_lower.jl")
elseif ["latest"] == ARGS || isempty(ARGS)
    using EcologicalNetworksDynamics
else
    error("Invalid test arguments: $ARGS")
end

# Testing utils.
include("./utils.jl")
include("./test_failures.jl")
include("./dedicated_test_failures.jl")

# The whole testing suite has been moved to "internals"
# while we are focusing on constructing the library API.
sep("Test internals.")
include("./internals/runtests.jl")

sep("Test System/Blueprints/Components framework.")
include("./framework/runtests.jl")

sep("Test API utils.")
#! format: off
run_tests([
    "./topologies.jl"
    "./aliasing_dicts.jl"
    "./multiplex_api.jl"
]; parallel = false)
#! format: on
include("./graph_data_inputs/runtests.jl")

sep("Test user-facing behaviour.")
include("./user/runtests.jl")

sep("Run doctests (DEACTIVATED while migrating api from 'Internals').")
#  include("./doctests.jl")

sep("Check source code formatting.")
include("./formatting.jl")

sep("Check compatibility entries.")
CompatHelperLocal.@check()

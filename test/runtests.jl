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
import EcologicalNetworksDynamics: Display
import .Display: blue, bold, reset


# Draw separator.
sep(mess) = println("$blue$bold== $mess $(repeat("=", 80 - 4 - length(mess)))$reset")

sep("Test testing utils procedures.")
include("./tests.jl")
# ONHOLD: being much simplified maybe
# because there is no (much) need to test failing expanded macros anymore.
#  # Testing utils, each within their dedicated module,
#  # but also re-exported at toplevel
#  # for convenience within futher tests modules.
#  include("./test_failures.jl")
#  using .TestFailures
#  include("./dedicated_test_failures.jl")
#  using .DedicatedTestFailures

#  sep("Test internal model representation.")
#  include("./networks/runtests.jl")

#  sep("Test System/Blueprints/Components framework.")
#  include("./framework/runtests.jl")

#  sep("Test API utils.")
#  include("./convert.jl")
#  include("./aliasing_dicts.jl")
#  include("./multiplex_api.jl")

#  sep("Test user-facing behaviour.")
#  include("./user/runtests.jl")

#= Silent all this during internals refactoring.

# The whole testing suite has been moved to "internals"
# while we are focusing on constructing the library API.
sep("Test internals.")
include("./internals/runtests.jl")

include("./topologies.jl")

sep("Run doctests (DEACTIVATED while migrating api from 'Internals').")
#  include("./doctests.jl")
=#

# TODO: update after refactoring.
#  sep("Check source code formatting.")
#  include("./formatting.jl")
#  sep("Check compatibility entries.")
#  CompatHelperLocal.@check()

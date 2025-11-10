# Dedicate to exceptions emitted by various parts of the project.
# Export test macros to the various test submodules.
# TODO: ease boilerplate here.

using MacroTools
using .TestFailures

include("./dedicated_test_failures/aliasing.jl")
include("./dedicated_test_failures/framework.jl")
include("./dedicated_test_failures/graphviews.jl")

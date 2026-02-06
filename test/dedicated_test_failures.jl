# Dedicate to exceptions emitted by various parts of the project.
# Export test macros to the various test submodules.
# TODO: ease boilerplate here.

module DedicatedTestFailures

using MacroTools

using Main.TestFailures
export @failswith, @xargfails, @argfails

include("./dedicated_test_failures/network.jl")
include("./dedicated_test_failures/aliasing.jl")
include("./dedicated_test_failures/framework.jl")
include("./dedicated_test_failures/views.jl")

end

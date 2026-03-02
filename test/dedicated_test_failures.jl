# Dedicate to exceptions emitted by various parts of the project.
# Export test macros to the various test submodules.
# TODO: ease boilerplate here.

module DedicatedTestFailures

using MacroTools

using Main.TestFailures

include("./dedicated_test_failures/network.jl")
include("./dedicated_test_failures/aliasing.jl")
include("./dedicated_test_failures/framework.jl")
include("./dedicated_test_failures/network_framework.jl")
#  include("./dedicated_test_failures/views.jl") # XXX on hold?

export @netfails, @labelfails
export @xaliasfails, @aliasfails
export @bluefails, @methfails, @compfails, @conffails, @sysfails
export @inputfails

end

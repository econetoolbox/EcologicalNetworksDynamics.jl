module TestGraphDataInputs

using SparseArrays
using OrderedCollections

using EcologicalNetworksDynamics.GraphDataInputs
using ..TestFailures
using Test

import EcologicalNetworksDynamics: SparseMatrix, Framework
import .Framework: CheckError

#  include("./types.jl")
include("./convert.jl")
#  include("./check.jl")
#  include("./expand.jl")

end

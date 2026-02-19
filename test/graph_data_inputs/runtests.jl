module TestGraphDataInputs

using SparseArrays
using OrderedCollections

import EcologicalNetworksDynamics: SparseMatrix, Framework, GraphDataInputs

using .GraphDataInputs
import .Framework: CheckError

using Test
using Main: @xargfails, @argfails, @failswith

include("./types.jl")
include("./convert.jl")
#  include("./check.jl")
#  include("./expand.jl")

end

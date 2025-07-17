module TestGraphDataInputs

using SparseArrays
using OrderedCollections

using ..TestFailures

import EcologicalNetworksDynamics: SparseMatrix, Framework
import .Framework: CheckError

#! format: off
Main.run_tests([
    "types.jl",
    "convert.jl",
    "check.jl",
    "expand.jl",
]; parallel = false, prefix = "graph_data_inputs")
#! format: on

end

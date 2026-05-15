"""
The library dedicated to component authors.

It exposes functionalities of the system/blueprint/components framework,
yet in the specific context of writing components for values of type `Network`.

In other words, typical components in the package are expected to be:

  - Component bringing a class.
  - Component bringing a web.
  - Component bringing network-level data.
  - Component bringing node-level data.
  - Component bringing edge-level data.

.. each with their own typical set of blueprints, properties,
input checking/parsing, semantics.
This module aims to make it easy for component authors to do that.

User input may take various ergonomic forms, supported by this module,
but it essentially reflects the underlying graph structure
so it mostly falls into three categories:

  - Network (graph-level) data:

      + Scalar: *eg.* `5`.

  - Class (node-level) data:

      + Vector: *eg.* `[4, 5, 6]`

      + Sparse vector for 'masked' classes, considered from the perspective of a parent class:
        *eg.* `[·, 4, ·, ·, 5, ·, 6]`
      + Map (key-value pairs) of the form:

          * `[:a => u, :c => v]`   (using nodes labels)
          * `[1 => u, 3 => v]`     (using node indices, in the context of one particular class)
      + For convenience, nodes may be grouped:

          * `[(:a, :b) => u, (:c, :d) => v]`
          * `[(1, 2) => u, (3, 4) => v]`
      + For convenience, binary data are elided:

          * `[:a, :c]`
          * `[1, 3]`
  - Web (edge-level) data:

      + Matrix for dense webs.

      + Sparse matrix for sparse webs.
      + Matrix for dense webs, but then a default value must be identified
        and found in every non-entry.
      + Adjacency lists of the form:

          * Using node labels:

              - `[:a => (:b => u, :c => v), :b => (:d => w)]`  (group targets)
              - `[(:a => u, :b => v) => :c, (:b => w) => :d]`  (group sources)
              - `[(:a, :b) => (:c => u, :d => v)]`             (group both, target-wise)
              - `[(:a => u, :b => v) => (:c, :d)]`             (group both, source-wise)
              - `[(:a => u, :b => v) => :c, :b => (:d => w)]`  (mixing allowed)
              - `[(:a => u, :b => v) => :c, :b => (:d => w)]`  (mixing allowed)

          * Using node indices, in the context of one particular (source, target) class pair.

              - `[1 => (2 => u, 3 => v), 2 => (4 => w)]`       (using nodes indices)
              - *etc.*                                            ⋮
          * For convenience, binary data are elided:

              - `[:a => (:b, :c), :b => (:d,)]`  (group targets)
              - `[(:a, :b) => :c, (:b,) => :d]`  (group sources)
              - `[(:a, :b) => (:c, :d)]`         (group both)
              - `[(:a, :b) => :c, :b => (:d,)]`  (mixing)
              - `[1 => [2, 3], 2 => [4]]`
              - *etc.*
          * For convenience, allow singletons, unambiguous in this context:

              - `[:a => :b, :b => :d]`# Define extension points to customize components behaviours.
              - `[1 => 2, 2 => 4]`
"""
module NetworkFramework

import EcologicalNetworksDynamics:
    EN,
    Networks,
    N,
    Framework,
    F,
    I,
    argerr,
    SparseMatrix,
    Option,
    KwargsHelpers,
    AD,
    FailedAttempts,
    render_input
using .Networks
using .Framework
using .KwargsHelpers

using Crayons
using OrderedCollections
using SparseArrays

const NF = NetworkFramework

# Define extension points to customize components behaviours.
include("dispatchers.jl")
using .Dispatchers
const D = Dispatchers

# Dedicate framework to the specific `Network` value.
include("framework.jl")

include("errors.jl")

include("./convert.jl")
include("./lists.jl")

# Typical views into network data.
include("./Views/Views.jl")
const V = Views

# Templates for typical network components.
include("./graph_scalar.jl")
include("./class.jl")
include("./web.jl")
include("./node_field.jl")
include("./sparse_node_field.jl")
include("./edges.jl")

include("./display.jl")

# ==========================================================================================
# Frequent specializations for checking values.

function non_negative(T, input)
    v = inputconvert(T, input)
    v < 0 && checkerr(v, "Value cannot be negative. Received: $(repr(input))")
    v
end

function name_among(expected, input)
    name = inputconvert(Symbol, input)
    name in expected ||
        checkerr(name, "Expected one of $(EN.join_elided(expected, ", ", " or ")).")
    name
end

# Pick symbols from an aliased dict.
aliasing_symbol(dict, input) =
    try
        AD.standardize(input, dict)
    catch e
        e isa AD.AliasingError || rethrow(e)
        parserr(input, sprint(showerror, e), rethrow)
    end
end

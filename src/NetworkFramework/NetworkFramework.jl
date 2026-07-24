raw"""
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
    - Scalar: *eg.* `5`.

  - Class (node-level) data:
    - Vector: *eg.* `[4, 5, 6]`
    - Sparse vector for 'masked' classes, considered from the perspective of a parent class:
      *eg.* `[·, 4, ·, ·, 5, ·, 6]`
    - Map (key-value pairs) of the form:
      - `[:a => u, :c => v]`   (using nodes labels)
      - `[1 => u, 3 => v]`     (using node indices, in the context of one particular class)
    - For convenience, nodes may be grouped:
      - `[(:a, :b) => u, (:c, :d) => v]`
      - `[(1, 2) => u, (3, 4) => v]`
    - For convenience, binary data are elided:
      - `[:a, :c]`
      - `[1, 3]`

  - Web (edge-level) data:
    - Matrix for dense webs.
    - Sparse matrix for sparse webs.
    - Matrix for dense webs, but then a default value must be identified
      and found in every non-entry.
    - Adjacency lists of the form:
      - Using node labels:
        - `[:a => (:b => u, :c => v), :b => (:d => w)]`  (group targets)
        - `[(:a => u, :b => v) => :c, (:b => w) => :d]`  (group sources)
        - `[(:a, :b) => (:c => u, :d => v)]`             (group both, target-wise)
        - `[(:a => u, :b => v) => (:c, :d)]`             (group both, source-wise)
        - `[(:a => u, :b => v) => :c, :b => (:d => w)]`  (mixing allowed)
        - `[(:a => u, :b => v) => :c, :b => (:d => w)]`  (mixing allowed)
      - Using node indices, in the context of one particular (source, target) class pair.
        - `[1 => (2 => u, 3 => v), 2 => (4 => w)]`       (using nodes indices)
        - *etc.*                                            ⋮
      - For convenience, binary data are elided:
        - `[:a => (:b, :c), :b => (:d,)]`  (group targets)
        - `[(:a, :b) => :c, (:b,) => :d]`  (group sources)
        - `[(:a, :b) => (:c, :d)]`         (group both)
        - `[(:a, :b) => :c, :b => (:d,)]`  (mixing)
        - `[1 => [2, 3], 2 => [4]]`
        - *etc.*
      - For convenience, allow singletons, unambiguous in this context:
        - `[:a => :b, :b => :d]`# Define extension points to customize components behaviours.
        - `[1 => 2, 2 => 4]`

Here is the typical, default data flow, starting from arbitrary user input:
  - Parse:
    - Convert (to the right type).
    - Intrinsic check.

  - (Data)Blueprint:
    - Construct: parse.
    - Early check: intrinsic check (again) + data preprocess.
    - Late check (against model).
    - Expand.

  - (Data)Component (via *views*):

    - Index:
      - Check dimension.
      - Parse (index).
      - Check query (against model).
      - Obtain.

    - Mutate:
      - Select: index (before 'obtain').
      - Parse (rhs).
      - Early check.
      - Late check.
      - Commit.

Throughout the process, raise and upgrade the typical error types
to explain failure reason and upgrade context depending on position within the flow.
Authors should be able to focus on the core failur reason,
and assume that additional context *will* be introduced above to improve the error report.
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

# Dedicate framework to the specific `Network` value.
include("framework.jl")

# Define extension points to customize the data flow behaviour with fine grain.
include("dispatchers.jl")
const D = Dispatchers

include("errors.jl")

# Typical `blueprint` and `mutate` utils.
include("./dataflow.jl")

# Typical `parse` utils.
include("./convert.jl")
include("./lists.jl")

# Views and the `index` logic.
include("./Views/Views.jl")
const V = Views

# Templates for typical network blueprint/components.
include("./graph_scalar.jl")
include("./class.jl")
include("./web.jl")
include("./node_field.jl")
include("./subnode_field.jl")
include("./edge_field.jl")

include("./display.jl")

# ==========================================================================================
# Frequent specializations for checking values.

function non_negative(T, input)
    v = inputconvert(T, input)
    v < 0 && liberr(v, "Value cannot be negative.")
    v
end

function fraction(T, input)
    v = inputconvert(T, input)
    0.0 <= v <= 1.0 || liberr(v, "Value must belong to [0, 1].")
    v
end

function name_among(expected, input)
    name = inputconvert(Symbol, input)
    name in expected ||
        liberr(name, "Expected one of $(EN.join_elided(expected, ", ", " or ")).")
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

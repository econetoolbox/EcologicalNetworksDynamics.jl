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
    - Sparse vector for subclasses considered from the perspective of a parent class:
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
        - `[:a => :b, :b => :d]`
        - `[1 => 2, 2 => 4]`

There are several main "pipelines" that data may transit through
when flowing from raw user input to internal storage.
The various methods defined in this module are named after
the different steps in these pipelines.
With the name comes responsibility what to do with the data, specified below.
The module attempts to provide sensible defaults
but every method may be specialized depending on pipeline, data kind or blueprint.

- Pipeline "blueprint expansion": a blueprint type or value is available:

  - `construct`: transform input into checked blueprint fields. Consists in:

    - `convert` responsibilities:
      - Convert input to expected field type.
      - *Alias* input if already expected type. If possible no-op, static, O(1) process.
      - Raise exception in case conversion is impossible.

    - `intrinsic_check`: Responsibilities:
      - Verify converted value consistency against expected data kind. Out-of-context.
      - Raise exception in case the value does not make sense.

  - `early_check` responsibilities:
    - Verify blueprint value prior to expansion.
      This involves checking blueprint fields again
      because blueprint may have been mutated since construction.
    - Raise exception in case the value does not make sense.
    - If useful, take this opportunity to start the lowering process
      by collecting/transforming data to be passed to `late_check`.
    - Default to running `intrinsic_check` again with no lowering.

  - `late_check` responsibilities:
    - Verify blueprint value against model value,
      now available with all components required for expansion guaranteed inside.
    - Raise exception in case the value doesn't fit within the model.
    - If useful, continue the lowering process, producing data to be passed to `lower`.
    - Default to checking nothing and passing data as-is.

  - `lower` responsibilities:
    - Transform data passed by `late_check` into the eventual storage format.
    - Not fail.

  - `expand!` responsibilities:
    - Record lowered data into the the model.
    - Not fail.

- Pipeline "index": query model data for extraction. Only the data kind is available.
  This is not open for extension by component authors within the lib like the above
  so the implementation is separate, although principles are the same.
  - Check the index (same responsibility although different specialized steps):
    - `check_dim`: raise on meaningless dimensions queried (*e.g.* 2D node data).
    - `check_type`: raise on invalid index type, allowing for a few restricted conversions.
    - `check_value`: raise on meaningless index value.
    - `check_query`: raise on mismatch between index value and model value.
  - `obtain`: retrieve the desired data. Cannot fail.

- Pipeline "data mutation": happens after expansion, the data kind is available as context.
  Most steps share responsibilities with the ones in pipelines above, and default to them:
  - Index check: like above to determine the target "LHS" data (mutation is `RHS = LHS`).
  - `convert` the RHS.
  - `early_check` the RHS.
  - `late_check` the RHS.
  - `commit`: record mutation result into the internal representation. Cannot fail.

The above steps are default-configured within the lib for typical component types,
and are exposed as possible extension points to component authors.
When implementing `*_check()` steps, raise using the simplest exception message.
The library should catch it and append relevant context before it bubbles up to user.
"""
module NetworkFramework

import EcologicalNetworksDynamics:
    EN, Networks, N, Framework, F, I, argerr, SparseMatrix, Option, KwargsHelpers, AD,
    FailedAttempts, Display
import .Display: render_input, black, reset

using Crayons
using OrderedCollections
using SparseArrays

const NF = NetworkFramework

# Dedicate framework to the specific `Network` value.
include("framework.jl")

# Define extension points to customize the data flow behaviour with fine grain.
include("dispatchers.jl")
using .Dispatchers: Dispatcher
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
#  include("./class.jl")
#  include("./web.jl")
#  include("./node_field.jl")
#  include("./subnode_field.jl")
#  include("./edge_field.jl")

include("./display.jl")

# ==========================================================================================
# Frequent specializations for checking values.

function non_negative(T, input)
    v = convert(T, input)
    v < 0 && liberr(v, "Value cannot be negative.")
    v
end

function fraction(T, input)
    v = convert(T, input)
    0.0 <= v <= 1.0 || liberr(v, "Value must belong to [0, 1].")
    v
end

function name_among(expected, input)
    name = convert(Symbol, input)
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

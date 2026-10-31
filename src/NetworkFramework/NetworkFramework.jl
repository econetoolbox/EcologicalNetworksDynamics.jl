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

There are several main "pipelines" that data transits through
when flowing from raw user input to internal storage.
The various methods defined in this module are named after
these pipelines and the different steps in them.
With the name comes responsibility what to do with the data, as specified below.
The module attempts to provide sensible defaults
but every method may be specialized depending on pipeline, data kind or blueprint.
Unless otherwise stated,
every step is implicitly responsible for raising adequate exception in case of failure.

- Pipeline "blueprint construction" `cst`:
  only raw input and the data type are available.
  The total, final output data must alias the original input if already correct.
  This responsibility therefore weights on every step.

    - `convert`:
        - Convert raw input to expected inner type.
        - *Alias* input if already expected type. If possible no-op, static, O(1) process.

    - `early_check`:
      - Verify converted value consistency against expected data kind. Out-of-context.
      - *Alias* input. No-op, static, O(1), whenever possible.
      - Return data ready to feed into `new`.

- Pipeline "blueprint expansion" `bp`: a blueprint value is available as input.
  Every step may or may not locally alias input,
  but the total, final output data, if mutable
  *must not* alias the original blueprint value.
  In other words, aliasing, if mutable, *must* be lost along this pipeline chain.

  - `early_check`:
    - Verify blueprint value prior to expansion,
      because it may have muted since construction.
    - If possible, start lowering data towards internal storage format.

  - `imply`:
    - If any blueprint is implied: construct and expand it. Should not fail.

  - `late_check`: a model value becomes available to verify against.
    - Verify blueprint value against the given model value,
      now available with all components required for expansion guaranteed inside.
    - If useful, continue the lowering process, producing data to be passed to `lower`.

  - `lower`:
    - Transform data passed by `late_check` into the eventual storage format.
    - Not fail.

  - `expand!`:
    - Record lowered data into the the model.
    - Not fail.

- Pipeline "data mutation" `mut`:
  happens after expansion, the data kind is available as context.
  Like above, the total, final output cannot be an alias,
  although the internal storage already makes this difficult to happen unintentionally.
  Interestingly, the data flowing through this pipeline may be only *partial*,
  so completeness checks can be disabled.
  - `convert`: see above.
  - `early_check`: see above: may not alias to start lowering, no completeness check.
  - `late_check`: see above.
  - `lower`: see above.
  - `commit`: record mutation result into the internal representation. Cannot fail.

The above steps are default-configured within the lib for typical component types,
and are exposed as possible extension points to component authors.
When implementing `*_check()` steps, raise using the simplest exception message.
The library should catch it and append relevant context before it bubbles up to user.
"""
module NetworkFramework

using EcologicalNetworksDynamics:
    EN, Networks, N, Framework, F, I, argerr, SparseMatrix, Option, KwargsHelpers, AD,
    FailedAttempts, Display, errwith, unimplemented, paste_paths
using .Display: render_input, green, cyan, black, reset, join_elided, rept, ns, nsa
using .Networks: Topology
using .Framework: bpdisplay, bpcol

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

# View types.
include("./Views/Views.jl")
const V = Views

# With all this set up, components can now be authored.
# But most of them look very much alike,
# so gather default implementation for typical ones.
include("./graph_field.jl")
include("./class.jl")
#  include("./web.jl")
#  include("./node_field.jl")
#  include("./subnode_field.jl")
#  include("./edge_field.jl")

# Typical allometry-related blueprints.
include("./allometry.jl")

include("./display.jl")

# ==========================================================================================
# Frequent specializations for checking values.

function non_negative(T, input)
    v = convert(T, input)
    v >= 0 && return v
    checkerr(v, "Value cannot be negative.")
end

function fraction(T, input)
    v = convert(T, input)
    0.0 <= v <= 1.0 && return v
    checkerr(v, "Value must belong to [0, 1].")
end

function name_among(expected, input)
    name = convert(Symbol, input)
    name in expected && return name
    checkerr(name, "Expected one of $(join_elided(expected, ", ", " or ")).")
end

# Pick symbols from an aliased dict.
aliasing_symbol(dict, input) =
    try
        AD.standardize(input, dict)
    catch e
        e isa AD.AliasingError || rethrow(e)
        checkerr(input, e, rethrow) # TODO: this will fail. Newtype in an NF.RootCause?
    end

using .Views
export extract

end

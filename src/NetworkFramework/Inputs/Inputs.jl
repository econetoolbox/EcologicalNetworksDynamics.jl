"""
This module aims at factorizing typical user input preprocessing:
parsing, converting, intrinsic checking, contextualized checking, transforming..
altogether referred to as 'absorbing'.
Input is absorbed when constructing blueprints,
when early-checking or late-checking them,
and when mutating values through model views.

User input may take various ergonomic forms,
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
          - `[:a => :b, :b => :d]`
          - `[1 => 2, 2 => 4]`

### Conversions.

Flexibility is allowed on the input type,
with the following conversions implicitly performed:

- (*) `Real -> Float64` (in particular: `Integer -> Float64`)
- (*) `Integer` -> Bool` (let julia guard against values other than `0` or `1`)
- (*) `Integer` -> Int64`
- `(Symbol, Char) -> String`
- `(AbstractString, Char) -> Symbol`

Conversions marked with (*) are also implicitly performed on collections types.
For `Coll` in `{Vector, Matrix, SparseVector, SparseMatrix}`:

- `Coll{<:Real} -> Coll{Float64}`
- `Coll{<:Integer} -> Coll{Bool}`
- `Coll{<:Integer} -> Coll{Int64}`

Additionally:

- `Vector{*} -> SparseVector{*}`
- `Matrix{*} -> SparseMatrix{*}`

No other conversion is implicitly performed yet.

Matching julia's `convert` behaviour,
if there is no need to construct or convert to a new value,
then the original value is used, and so the user keeps an *aliased reference* to it.
This makes it possible for user to avoid unnecessary copies
at the cost of providing the exact correct type.

### Parsing maps.

Any iterable input structured like:

```
[
  [Ref, T],
  [(Ref, ...), T], # (grouped nodes)
  ...,
]
```

is accepted and parsed as a nodes data map.

In the special case of binary data (`T = Bool`), any iterable input like:

```
[Ref, ...]
```

is accepted and parsed into a nodes mask.

In either case, duplicated 'Ref' keys are rejected.

### Parsing adjacency lists.

Any iterable input structured like:
```
[
  [Ref, ([Ref, T], ...)], # (grouped targets)
  [([Ref, T], ...), Ref], # (grouped sources)
  ...,
]
```
is accepted and parsed into an edges data adjacency list.

In the special case of binary data (`T = Bool`), any iterable input like:
```
[
  [Ref, (Ref, ...)], # (grouped targets)
  [(Ref, ...), Ref], # (grouped sources)
  ...,
]
```

is accepted and parsed into an edges adacency list.

In either case, duplicated 'Ref' keys are rejected, on source either source or target side.

"""
module Inputs

import EcologicalNetworksDynamics: EN, N, F, I, Option, SparseMatrix, argerr

using Crayons
using SparseArrays
using OrderedCollections

# Absorbing maps and adjacency lists produces values of the following types.
# The `R`eference type is either inferred to Int (index) or Symbol (label)
# depending on user input.
const Map{R,T} = OrderedDict{R,T}
const BinMap{R} = OrderedSet{R}
const Adjacency{R,T} = OrderedDict{R,OrderedDict{R,T}}
const BinAdjacency{R} = OrderedDict{R,OrderedSet{R}}
export Map, Adjacency, BinMap, BinAdjacency

"""
The main function exposed here.
Either call with a target type to convert,
with a particular dispatcher to perform component-specific values (early) checks,
with model context and particular access to perform component-specific values (late) checks,
prior to blueprint expansion or prior to mutating through views.
Responsibilities: parse, check, convert.
Raise `inerr("simple message")` to obtain a contextualized error in case anything fails.
"""
function absorb end
export absorb

include("./convert.jl")
include("./lists.jl")
include("./check.jl")
include("./expand.jl")

struct InputError <: Exception
    mess::String
end
inerr(m, throw = Base.throw) = throw(InputError(m))
export InputError, inerr

end

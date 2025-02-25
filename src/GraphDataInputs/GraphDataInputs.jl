# This module aims at factorizing out the most typical user input preprocessing.
# Since the underlying ecological model value essentially constitutes a *graph*,
# then data input by user mostly falls into three categories:
#
# TODO: the 'template'/'filter' thing gets pervasive,
#       include it deeply within this core logic instead.
# TODO: this module hooks into something deeply related
#       with how the graph modelling in this package goes.
#       It deserves to be integrated much better with the rest of the framework.
#
# - Graph data:
#   - Scalar.
#
# - Node data:
#   - Vector.
#   - Sparse vector if the data only concerns a subset of nodes
#     eg. "producers".
#   - Map (key-value pairs) of the form:
#       [:a => u, :c => v]   (using nodes labels)
#       [1 => u, 3 => v]     (using node indices)
#     convenience factorized form, grouping nodes:
#       [(:a, :b) => u, (:c, :d) => v]
#       [(1, 2) => u, (3, 4) => v]
#     or, special-casing binary data:
#       [:a, :c]
#       [1, 3]
#
#  - Edge data:
#    - Matrix.
#    - Sparse matrix if the data only concerns a subset of possible edges
#      eg.: "trophic links"
#    - Adjacency list of the form:
#       [:a => (:b => u, :c => v), :b => (:d => w)]  (grouping targets)
#       [(:a => u, :b => v) => :c, (:b => w) => :d]  (grouping sources)
#       [(:a => u, :b => v) => :c, :b => (:d => w)]  (mixing allowed)
#      or
#       [1 => (2 => u, 3 => v), 2 => (4 => w)]       (using nodes indices)
#       ⋮                                            ⋮
#      or, special-casing binary edge data:
#       [:a => (:b, :c), :b => (:d,)]  # (grouping targets)
#       [(:a, :b) => :c, (:b,) => :d]  # (grouping sources)
#       [(:a, :b) => :c, :b => (:d,)]  # (mixing)
#       [1 => [2, 3], 2 => [4]]
#       ⋮
#       (allowed because singletons are unambiguous in this context)
#       [:a => :b, :b => :d]
#       [1 => 2, 2 => 4]
#
#
# All values need to be checked according to their own semantics and context,
# but we can use this module to factorize common structure checking:
#
# - Graph data:
#
#   - Scalar: only context-specific checks (nothing to factorize here).
#
# - Node data:
#
#   - Vector: check that the length matches the number of nodes in the target compartment.
#             eg.: [3 3 3] invalid if "there are only 2 species".
#
#   - Sparse vector: also check that no value is provided for an unexistent node.
#                    (check that it has correct 'template')
#             eg.: [3 · 3] invalid if "the 1st species is not a producer".
#
#   - Map: check that all nodes labels/indices are defined/allowed,
#          and that no value is specified twice.
#          If a template is provided, check against the template.
#
# - Edge data:
#
#   - Matrix: check that the size matches the expected n_source × n_target compartments.
#             eg. [1 2 3
#                  4 5 6] invalid size if "there are 2 species but 4 nutrients (not 3)".
#
#   - Sparse matrix: also check that no value is provided for an unexistent edge.
#                    (check that it has correct 'template')
#             eg. [1 · 2
#                  3 4 ·] invalid value '3' if "species 2 does not feed on nutrient 1".
#
#   - Adjacency list: check all that node id labels/indices are defined/allowed,
#                     and that no value is specified twice.
#                     If a template is provided, check against the template.
#
# ==========================================================================================
# Flexibility is allowed on the input, with the following conversions implicitly performed:
#
#   * Real -> Float64 (in particular: Integer -> Float64)
#   * Integer -> Bool (and julia guard against values other than '0' or '1')
#   * Integer -> Int64
#   - (Symbol, Char) -> String
#   - (AbstractString, Char) -> Symbol
#
# The conversions marked with a '*' only,
# conversion is also implicitly performed for collections types.
#
#
# For 'Coll' in {Vector, Matrix, SparseVector, SparseMatrix}: ------------------------------
#
#   - Coll{<:Real} -> Coll{Float64}
#   - Coll{<:Integer} -> Coll{Bool}
#   - Coll{<:Integer} -> Coll{Int64}
#
# And additional:
#
#   - Vector{*} -> SparseVector{*}
#   - Matrix{*} -> SparseMatrix{*}
#
# For maps, any iterable input structured like: --------------------------------------------
#
#   [
#     [Id, T],
#     [(Id, ...), T], # (grouped nodes)
#     ...,
#   ]
#
# is accepted and transformed into:
#
#   OrderedDict{Id,T}
#
# Or in the special binary, any iterable input like:
#
#   [Id, ...]
#
# is accepted and transformed into:
#
#   OrderedSet{Id}
#
# In either case, duplicated 'Id' keys are rejected.
#
#
# For adjacency lists, any iterable input structured like: ---------------------------------
#
#   [
#     [Id, ([Id, T], ...)], # (grouped targets)
#     [([Id, T], ...), Id], # (grouped sources)
#     ...,
#   ]
#
# is accepted and transformed into:
#
#   OrderedDict{Id,OrderedDict{Id, T}}
#
# Or in the special binary case, any iterable input like:
#
#   [
#     [Id, (Id, ...)], # (grouped targets)
#     [(Id, ...), Id], # (grouped sources)
#     ...,
#   ]
#
# is accepted and transformed into:
#
#   OrderedDict{Id,OrderedSet{Id}}
#
# In either case, duplicated 'Id' keys are rejected.
#
# No other conversion is implicitly performed,
# but the above remain open to future evolution.
#
# ==========================================================================================
# In addition, and for user convenience,
# values can be automatically constructed from various types
# according to the semantics described below.
#
# Matching julia's `convert` behaviour,
# if there is no need to construct or convert to a new value,
# then the original value is used, and so the user keeps an *aliased reference* to it.
# This makes it possible for user to avoid unnecessary copies
# at the cost of providing the exact correct type.
#
# - Graph data: if given: ------------------------------------------------------------------
#
#   - Symbol: construct according to the named procedure:
#             eg.: :standard_temperature -> 293.15
#
#   - Scalar: check and use as-is.
#
#
# - Node data: -----------------------------------------------------------------------------
#
#     - Vector expected: if given: - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       - Symbol: construct according to the named procedure.
#
#       - Scalar: use to construct a homogeneous vector with the correct length.
#                 eg.: 3 -> [3 3 3 3 3]
#
#       - Vector: check and use as-is.
#                 The result is an *alias* if no conversion was needed.
#
#       - Map: check that no value is missing, fill from the indexed pairs.
#
#     - Sparse vector expected: if given: - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       - Symbol: construct according to the named procedure.
#
#       - Scalar: use to construct a homogeneous sparse vector with correct template.
#                 eg.: 3 -> [· 3 · · 3]
#
#       - Vector in a "values" context:
#                 use to construct the nonzero values with correct template.
#                 eg.: [1 2] -> [· 1 · · 2]
#
#       - Vector: convert to a sparse vector then check for template.
#
#       - Sparse vector: check and use as-is.
#                        The result is an *alias* if no conversion was needed.
#
#       - Map: fill from the indexed pairs.
#
# - Edge data: -----------------------------------------------------------------------------
#
#     - Matrix expected: if given: - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       - Symbol: construct according to the named procedure.
#
#       - Scalar: use to construct a homogeneous matrix with the correct size.
#                 eg.: 3 -> [3 3 3
#                            3 3 3]
#
#       - Vector in a "row" context: use to construct a correct row-wise matrix:
#                eg.: [1 2 3] -> [1 2 3
#                                 1 2 3]
#
#       - Vector in a "column" context: use to construct a correct col-wise matrix:
#                eg.: [1 2] -> [1 1 1
#                               2 2 2]
#
#       - TODO: Map in a "row" or "column" context?
#
#       - Matrix: check and use as-is.
#                 The result is an *alias* if no conversion was needed.
#
#       - TODO: adjacency lists?
#
#     - Sparse matrix expected: if given: - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       - Symbol: construct according to the named procedure.
#
#       - Scalar: use to construct a homogeneous sparse matrix with correct template.
#                 eg.: 3 -> [· 3 ·
#                            3 · 3]
#
#       - Vector in a "row" context: use to construct a templated row-wise matrix:
#                eg.: [1 2 3] -> [· 2 3
#                                 1 · 3]
#
#       - Vector in a "column" context: use to construct a templated col-wise matrix:
#                eg.: [1 2] -> [· 1 1
#                               2 · 2]
#
#       - Matrix: convert to a sparse matrix then check for template.
#
#       - Sparse Matrix: check and use as-is.
#                        The result is an *alias* if no conversion was needed.
#
#       - TODO: Map in a "row" or "column" context?
#
#       - Adjacency list: fill from the indexed pairs.
#
# ==========================================================================================
module GraphDataInputs

using Crayons
using MacroTools
using SparseArrays
using OrderedCollections

import ..SparseMatrix
import ..argerr
import ..Framework: checkfails
import ..join_elided

# Unhygienically define `loc` variable in macros to point to invocation line.
# Assumes __source__ is available.
macro defloc()
    esc(quote
        loc = "$(crayon"blue")\
               $(__source__.file):$(__source__.line)\
               $(crayon"reset")"
    end)
end
@macroexpand @defloc

include("./types.jl")
include("./convert.jl")
include("./check.jl")
include("./expand.jl")

end

# Not all possible inputs are expected for every blueprint field.
# For instance, one particular piece of edge data
# can be accepted as a scalar or a matrix,
# but not as a vector or a symbol.
# A typical field type for such an input would be:
#
#   field::Union{Float64, Matrix{Float64}}
#
# But this can get verbose:
#
#   field::Union{Symbol, Float64, Vector{Float64}, SparseMatrix{Float64}}
#
# To ease the specification of which possible input is allowed,
# convenience macros use the following aliases:
#
#   - Symbol ~ Sym ~ Y
#   - Scalar ~ Scal ~ S
#   - Vector ~ Vec ~ V
#   - Matrix ~ Mat ~ M
#   - SparseVector ~ SpVec ~ N (for 'nodes')
#   - SparseMatrix ~ SpMat ~ E (for 'edges')
#   - Map ~ K                  (for 'keys')
#   - Adjacency ~ Adj ~ A
#
# Single letters can be combined into a symbol, other shortened name between {} brackets:
# eg. `YSN{T}` is like `{Sym, Scal, SpMat}{T}` and means `Union{Symbol,T,SparseMatrix{T}}`.
#
# For maps and adjacency lists, use `:bin` instead of a type parameter
# to trigger the special binary case.

# I is either inferred to Int64 or Symbol depending on user input.
const Map{I,T} = OrderedDict{I,T}
const Adjacency{I,T} = OrderedDict{I,OrderedDict{I,T}}
const BinMap{I} = OrderedSet{I}
const BinAdjacency{I} = OrderedDict{I,OrderedSet{I}}
export Map, Adjacency, BinMap, BinAdjacency

const AbstractMap{I,T} = AbstractDict{I,T}
const AbstractAdjacency{I,T} = AbstractDict{I,<:AbstractDict{I,T}}
const AbstractBinMap{T} = AbstractSet{T}
const AbstractBinAdjacency{I} = AbstractDict{I,<:AbstractSet{I}}

aliases = OrderedDict(
    # Special cases.
    Symbol => [:Symbol, :Sym, :Y], # (non-parametric: "Symbol{T} = Symbol")
    :Scalar => [:Scalar, :Scal, :S], # (raw type: "Scalar{T} = T")
    # Regular parametric cases.
    Vector => [:Vector, :Vec, :V],
    Matrix => [:Matrix, :Mat, :M],
    SparseVector => [:SparseVector, :SpVec, :N],
    SparseMatrix => [:SparseMatrix, :SpMat, :E],
    # Double parametric cases, special-cased on ':bin'.
    :Map => [:Map, :K],
    :Adjacency => [:Adjacency, :Adj, :A],
)
rev_aliases = Dict(v => k for (k, vs) in aliases for v in vs)
als = repr(MIME("text/plain"), aliases) # (to include in error messages)

# ==========================================================================================
# Convenience union definition for blueprint field types.

# Transform input expression into a list of types.
# Accepted input:
#   @macro ... {Symbol, Scal} # (shortened names)
#   @macro ... YSN            # (single letters)
#   @macro ... {YSN}          # (convenience twist)
#   @macro ... Symbol         # (convenience twist if it matches a full name)
function parse_types(loc, input)
    if input isa Symbol
        if haskey(rev_aliases, input)
            specs = [input]
        else
            specs = Symbol.(collect(String(input)))
        end
    elseif input.head == :braces
        specs = Symbol.(input.args)
    else
        argerr("Invalid macro input at $loc:\n\
                Expected a braced-list of type aliases among:\n$als\n\
                Received instead: $(repr(input)).")
    end
    if length(specs) == 1 && !haskey(rev_aliases, first(specs))
        # Assume the {YSN} form has been given.
        specs = Symbol.(collect(String(first(specs))))
    end
    map(specs) do s
        haskey(rev_aliases, s) || argerr("Invalid type specification at $loc.\n\
                                          The received symbol $(repr(s)) \
                                          is not a valid type alias among:\n$als")
        rev_aliases[s]
    end
end

# Introduce parametric type in the above results, for instance with Float64:
#  Symbol -> Symbol
#  Scalar -> Float64
#  Vector -> Vector{Float64}
#  Map -> Map{I,Float64} where {I}   (id type still unspecified)
#
# But if T is `:bin`:
#  Map -> BinMap{I} where {I}
#
function expand_types(loc, types, T)
    # Covariant input like <:Real should not be used as-is for :Scalar.
    special_bin = false
    if T isa Expr && T.head == :<:
        Cov, T = esc(T), esc(T.args[1])
    elseif T isa QuoteNode
        T == :(:bin) || argerr("Invalid type specification at $loc.\n\
                                Did you bin :bin instead of $T?")
        special_bin = true
        Cov = T = :(Bool)
    elseif isnothing(T)
        all(types .== Symbol) || argerr("No type provided.")
    else
        Cov = T = esc(T)
    end
    map(types) do P
        P == :Scalar && return T
        P === Symbol && return Symbol
        if P in (:Map, :Adjacency)
            if special_bin
                BinP = Symbol(:Bin, P)
                :($BinP{I} where {I})
            else
                :($P{I,$Cov} where {I})
            end
        else
            :($P{$Cov})
        end
    end
end

# Do both.
parse_types(loc, input, T) = expand_types(loc, parse_types(loc, input), T)

# ==========================================================================================
# The actual exposed macro.

# Example usage:
#   @GraphData {Sym, Scal, SpVec}{Float64}
#   @GraphData YSN{Float64}
macro GraphData(input)
    @defloc
    @capture(input, types_{T_} | types_{})
    isnothing(types) && argerr("Invalid @GraphData input at $loc.\n\
                                Expected @GraphData {aliases...}{Type}. \
                                Got $(repr(input)).")
    types = parse_types(loc, types, T)
    u = :(Union{})
    append!(u.args, types)
    u
end
export @GraphData

# ==========================================================================================
# Analyse references in lists.
# 'index' is an integer used to access data.
# 'label' is a symbol used to access data.
# 'reference' is either and index or a label.
# 'access' is a homogeneous tuple of references use to access data: either (i,) or (i, j).
# 'Space' is the set of all possible references.
# 'Index' is a {label -> index} mapping (/!\ yes, same name as 'index').

# Aliases clarifying dispatch.
const UMap{I} = Union{BinMap{I},Map{I,<:Any}}
const UAdjacency{I} = Union{BinAdjacency{I},Adjacency{I,<:Any}}
const UBinList{I} = Union{BinMap{I},BinAdjacency{I}}
const UNonBinList{I} = Union{Map{I},Adjacency{I}}
const UList{I} = Union{UMap{I},UAdjacency{I}}
const Index = AbstractDict{Symbol,Int64}

# Iterate over all references present in the list.
refs(l::BinMap) = l
refs(l::Map) = keys(l)

# The two levels in adjacency lists
# are not necessarily the same reference space.
refs_outer(l::UAdjacency) = keys(l)
refs_inner(l::UAdjacency) = OrderedSet(Iterators.flatten(refs(sub) for (_, sub) in l))
# Unless we assume so.
refs(l::UAdjacency) =
    OrderedSet(ref for (i, sub) in l for ref in Iterators.flatten(((i,), refs(sub))))

# Count references present in the list.
nrefs(l::UList) = length(refs(l))
nrefs_outer(l::UAdjacency) = length(refs_outer(l))
nrefs_inner(l::UAdjacency) = length(refs_inner(l))

# Extrapolate total number of references in the reference space.
# Assuming contiguity, infer missing integers.
nrefspace(l::UList{Int64}) = maximum(refs(l); init = 0)
nrefspace(l::UList{Symbol}) = nrefs(l) # Cannot guess missing symbols.
nrefspace_outer(l::UAdjacency{Int64}) = maximum(refs_outer(l))
nrefspace_inner(l::UAdjacency{Int64}) = maximum(refs_inner(l))
nrefspace_outer(l::UAdjacency{Symbol}) = nrefs_outer(l)
nrefspace_inner(l::UAdjacency{Symbol}) = nrefs_inner(l)

# Infer total references space.
# In the integer case, the 'space' is reduced to a single number.
refspace(l::UList{Int64}) = nrefspace(l) # Assume contiguity.
refspace_outer(l::UAdjacency{Int64}) = nrefspace_outer(l)
refspace_inner(l::UAdjacency{Int64}) = nrefspace_inner(l)

# In the symbol case, the reference space is actually an 'Index'.
todict(refs) = OrderedDict(ref => i for (i, ref) in enumerate(refs))
refspace(l::UList{Symbol}) = todict(refs(l))
refspace_outer(l::UAdjacency{Symbol}) = todict(refs_outer(l))
refspace_inner(l::UAdjacency{Symbol}) = todict(refs_inner(l))

export refs, refs_outer, refs_inner
export nrefs, nrefs_outer, nrefs_inner
export nrefspace, nrefspace_outer, nrefspace_inner
export refspace, refspace_outer, refspace_inner

# 'Accesses' are used to index into the data.
# [i] for 1D maps and [i, j] for 2D adjacency lists.
# List the ones found in input.
accesses(l::UMap) = ((r,) for r in refs(l))
accesses(l::UAdjacency) = ((i, j) for (i, sub) in l for (j,) in accesses(sub))
get_value(l::Map, (ref,)) = l[ref]
get_value(l::Adjacency, (i, j)) = l[i][j]
get_value(l::BinMap, (ref,)) = ref in l
get_value(l::BinAdjacency, (i, j)) = j in l[i]

# Check that a references space contains any possible access.
empty_space(n::Int64) = n <= 0
empty_space(x::Index) = isempty(x)
empty_space((a, b)) = empty_space(a) || empty_space(b)

# Check an access against a reference space.
inspace((i,)::Tuple{Int64}, n::Int64) = 0 < i <= n
inspace((s,)::Tuple{Symbol}, x::Index) = s in keys(x)
inspace((a, b), (x, y)) = inspace((a,), x) && inspace((b,), y)

# ==========================================================================================
# Single entrypoint to iterate over either nodes/edges collections
# and always yield (ref, value) pairs.
# `ref` is either (i,), (i, j),  (:ref,) or (:ref1, :ref2) depending on the input.

# Base methods work with any iterable type (or nested).
node_items(pairs) = (((i,), v) for (i, v) in pairs)
edge_items(sup) = (((i, j), v) for (i, sub) in sup for ((j,), v) in node_items(sub))

# Specialize with further types semantics.
node_items(v::Vector) = node_items(enumerate(v))
edge_items(v::Vector) = edge_items(enumerate(v))
node_items(::AbstractMatrix) = throw("Cannot read node data from a 2D matrix.")
edge_items(m::AbstractMatrix) =
    (((i, j), v) for (i, row) in enumerate(eachrow(m)) for (j, v) in enumerate(row))
node_items(v::SparseVector) = (((i,), v) for (i, v) in zip(findnz(v)...))
edge_items(m::SparseMatrixCSC) = (((i, j), v) for (i, j, v) in zip(findnz(m)...))

# Automatic dispatch.
items(v::AbstractVector) = node_items(v)
items(m::AbstractMatrix) = edge_items(m)
items(d::AbstractDict) = node_items(d)
items(a::AbstractDict{<:Any,<:AbstractDict}) = edge_items(a)
export node_items, edge_items, items

# ==========================================================================================
# Pretty display for maps and adjacency lists.

disp_access(access::Tuple) = "[$(join(repr.(access), ", "))]"

display_short(map::Map) = "{$(join(("$(repr(k)): $v" for (k, v) in map), ", "))}"
function display_long(map::Map; level = 0)
    res = "{"
    ind(n) = "\n" * repeat("  ", level + n)
    for (k, v) in map
        res *= ind(1) * "$(repr(k)) => $v,"
    end
    res * ind(0) * "}"
end

display_short(map::BinMap) = "{$(join(("$(repr(k))" for k in map), ", "))}"
function display_long(map::BinMap; level = 0)
    res = "{"
    ind(n) = "\n" * repeat("  ", level + n)
    for k in map
        res *= ind(1) * "$(repr(k)),"
    end
    res * ind(0) * "}"
end

display_short(adj::Union{Adjacency,BinAdjacency}) =
    "{$(join(("$(repr(k)): $(display_short(list))" for (k, list) in adj), ", "))}"
function display_long(adj::Union{Adjacency,BinAdjacency}; level = 0)
    res = "{"
    ind(n) = "\n" * repeat("  ", level + n)
    for (k, list) in adj
        res *= ind(1) * "$(repr(k)) => $(display_long(list; level = level + 1)),"
    end
    res * ind(0) * "}"
end

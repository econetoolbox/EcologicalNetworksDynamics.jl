# Anticipate future refactoring of the internals with this 'view' pattern.
#
# Values stored within an array today
# may not always be available under this form.
# Yet, properties like model.my_favourite_biorates need to keep working like arrays,
# and also to protect against illegal writes.
# To this end, design a special "View" into internals data,
# under the form of newtypes implementing AbstractArray interface.
#
# Assume that the internals will always provide at least
# a cached array version of the data,
# and reference this cache directly from the view.
# Implementors then just need to define how the data
# is supposed to be accessed or updated.
#
# HERE: the internal data is now consistent and wrapped in `Networks.Entry`.
# Have the new views reflect that.
#
# Subtypes needs to be "fat slices" with the following fields:
#
#   ._ref:
#     Direct reference to the encapsulated data (possibly within the cache).
#
#   ._graph:
#     Direct reference to the overall graph model.
#
#   ._template: (optional)
#     Referenced or owned boolean mask
#     useful to forbid sparse data writes where not meaningful.
#
#   ._index (for nodes) or (._row_index, ._col_index) (for edges): (optional)
#     Referenced or owned mapping to convert symbol labels to integers.
#
# A convenience macro is defined outside this module
# to avoid having to manually define these fields,
# to correctly wire index/label checking depending on their presence
# and to integrate the view with the component Framework @methods.

module GraphViews

import ..Internal
using ..Display
using ..Networks
using SparseArrays

const Option{T} = Union{Nothing,T}

# ==========================================================================================
# Dedicated exception.

struct ViewError <: Exception
    type::Type # (View type)
    message::String
end
Base.showerror(io::IO, e::ViewError) = print(io, "View error ($(e.type)): $(e.message)")

# ==========================================================================================
# Base type hierarchy.
# Define the plumbery methods to make views work.
# No magic in here, so the ergonomics would be weak without helper macros.

# Accepted input for symbol labels.
Label = Union{Symbol,Char,AbstractString}
# Abstract over either index or labels.
Ref = Union{Int,Label}

# All views must behave like regular arrays.
abstract type AbstractGraphDataView{T,N} <: AbstractArray{T,N} end
abstract type AbstractSparseGraphDataView{T,N} <: AbstractSparseArray{T,Int,N} end

# Either 1D (for nodes data) or 2D (for edges data).
const AbstractNodesView{T} = AbstractGraphDataView{T,1}
const AbstractEdgesView{T} = AbstractGraphDataView{T,2}
const AbstractSparseNodesView{T} = AbstractSparseGraphDataView{T,1}
const AbstractSparseEdgesView{T} = AbstractSparseGraphDataView{T,2}

# Read-only or read/write versions (orthogonal to the above)
abstract type GraphDataReadOnlyView{T,N} <: AbstractGraphDataView{T,N} end
abstract type GraphDataReadWriteView{T,N} <: AbstractGraphDataView{T,N} end
abstract type SparseGraphDataReadOnlyView{T,N} <: AbstractSparseGraphDataView{T,N} end
abstract type SparseGraphDataReadWriteView{T,N} <: AbstractSparseGraphDataView{T,N} end

# Cartesian product of the above two pairs.
abstract type NodesView{T} <: GraphDataReadOnlyView{T,1} end
abstract type NodesWriteView{T} <: GraphDataReadWriteView{T,1} end
abstract type EdgesView{T} <: GraphDataReadOnlyView{T,2} end
abstract type EdgesWriteView{T} <: GraphDataReadWriteView{T,2} end
abstract type SparseNodesView{T} <: SparseGraphDataReadOnlyView{T,1} end
abstract type SparseNodesWriteView{T} <: SparseGraphDataReadWriteView{T,1} end
abstract type SparseEdgesView{T} <: SparseGraphDataReadOnlyView{T,2} end
abstract type SparseEdgesWriteView{T} <: SparseGraphDataReadWriteView{T,2} end
export NodesView
export NodesWriteView
export EdgesView
export EdgesWriteView
export SparseNodesView
export SparseNodesWriteView
export SparseEdgesView
export SparseEdgesWriteView

# Avoid methods dense/edge duplications.
const EitherAbstract{T,N} =
    Union{<:AbstractGraphDataView{T,N},<:AbstractSparseGraphDataView{T,N}}
const EitherNodes{T} = Union{<:AbstractNodesView{T},<:AbstractSparseNodesView{T}}
const EitherEdges{T} = Union{<:AbstractEdgesView{T},<:AbstractSparseEdgesView{T}}
const EitherReadOnly{T} = Union{<:GraphDataReadOnlyView{T},<:SparseGraphDataReadOnlyView{T}}
const EitherReadWrite{T} =
    Union{<:GraphDataReadWriteView{T},<:SparseGraphDataReadWriteView{T}}
const EitherReadNodes{T} = Union{<:NodesView{T},<:SparseNodesView{T}}
const EitherWriteNodes{T} = Union{<:NodesWriteView{T},<:SparseNodesWriteView{T}}
const EitherReadEdges{T} = Union{<:EdgesView{T},<:SparseEdgesView{T}}
const EitherWriteEdges{T} = Union{<:EdgesWriteView{T},<:SparseEdgesWriteView{T}}

# ==========================================================================================
# Defer base implementation to the ._ref field.

Base.size(v::EitherAbstract) = size(v._ref)
Base.:(==)(a::EitherAbstract, b::EitherAbstract) = a._ref == b._ref
SparseArrays.findnz(m::AbstractSparseGraphDataView) = findnz(m._ref)
SparseArrays.nonzeroinds(m::AbstractSparseGraphDataView) = SparseArrays.nonzeroinds(m._ref)
SparseArrays.nonzeros(m::AbstractSparseGraphDataView) = SparseArrays.nonzeros(m._ref)

# ==========================================================================================
# Checked access.

# Always valid for reading with indices (or we break AbstractArray contract).
function Base.getindex(v::EitherAbstract, index::Int...)
    check_access_dim(v, index...)
    check_dense_access(v, nothing, index) # Always do to harmonize error messages.
    getindex(v._ref, index...)
end

# Always checked for labelled access.
function Base.getindex(v::EitherAbstract, access::Label...)
    check_access_dim(v, access...)
    index = to_checked_index(v, access...)
    getindex(v._ref, index...)
end
Base.getindex(v::EitherAbstract) = check_access_dim(v) # (trigger correct error)

# Only allow writes for writeable views.
Base.setindex!(v::EitherReadWrite, rhs, access::Ref...) = setindex!(v, rhs, access)
Base.setindex!(v::EitherReadOnly, args...) =
    throw(ViewError(typeof(v), "This view into graph $(level_name(v))s data is read-only."))

function setindex!(v::EitherReadWrite, rhs, access)
    check_access_dim(v, access...)
    index = to_checked_index(v, access...)
    rhs = write!(v._graph, typeof(v), rhs, index)
    Base.setindex!(v._ref, rhs, index...)
end
inline_(access::Tuple) = join(repr.(access), ", ")
inline(access::Tuple) = "[$(inline_(access))]"
inline(access::Tuple, original) = "$(inline(access)) (=$(inline(original)))"
inline(access::Tuple, ::Tuple{Vararg{Int}}) = inline(access)
inline_size(access::Tuple) = "($(inline_(access)))"
inline_size(access::Tuple{Int64}) = "$(inline_(access))"

function to_checked_index(v::EitherAbstract, index::Int...)
    check_access(v, nothing, index)
    index
end

function to_checked_index(v::EitherAbstract, labels::Label...)
    index = to_index(v, labels...)
    check_access(v, labels, index)
    index
end

# Extension points for implementors.
check_access(v::EitherAbstract, _...) = throw("Unimplemented for $(typeof(v)).")
check_label(v::EitherAbstract, _...) = throw("Unimplemented for $(typeof(v)).")

# Check the value to be written prior to underlying call to `Base.setindex!`,
# and take this opportunity to possibly update other values within model besides ._ref.
# Returns the actual value to be passed to `setindex!`.
write!(::Internal, T::Type{<:EitherWriteNodes}, rhs, index) = rhs

# Name of the thing indexed, useful to improve errors.
item_name(::Type{<:EitherAbstract}) = "item"
item_name(v::EitherAbstract) = item_name(typeof(v))

level_name(::Type{<:EitherNodes}) = "node"
level_name(::Type{<:EitherEdges}) = "edge"
level_name(v::EitherAbstract) = level_name(typeof(v))

# ==========================================================================================
# All possible variants of additional index checking in implementors.

#-------------------------------------------------------------------------------------------
# Basic bound checks for dense views.

function check_dense_access(v::EitherAbstract, ::Any, index::Tuple{Vararg{Int}})
    all(0 .< index .<= size(v)) && return
    item = uppercasefirst(item_name(v))
    level = level_name(v)
    s = plural(length(v))
    z = size(v)
    throw(ViewError(
        typeof(v),
        "$item index $(inline(index)) is off-bounds \
        for a view into $(inline_size(z)) $(level)$s data.",
    ))
end
plural(n) = n > 1 ? "s" : ""

#-------------------------------------------------------------------------------------------
# For sparse views (a template is available as `._template`).

# Nodes.
function check_sparse_access(
    v::EitherAbstract,
    labels::Option{Tuple{Vararg{Label}}}, # Remember if given as labels.
    index::Tuple{Vararg{Int}},
)
    check_dense_access(v, labels, index)
    :_template in fieldnames(typeof(v)) || return # Always valid without a template.

    template = v._template
    template[index...] && return
    item = item_name(v)
    level = level_name(v)
    n = length(index)
    refs = if isnothing(labels)
        "index $(inline(index))"
    else
        "label$(n > 1 ? "s" : "") $(inline(labels)) ($(inline(index)))"
    end
    throw(
        ViewError(
            typeof(v),
            "Invalid $item $refs to write $level data. " *
            valid_refs_phrase(v, template, labels),
        ),
    )
end

function valid_refs_phrase(v, template, labels)
    valids = sort!(collect(valid_refs(v, template, labels)))
    if isempty(valids)
        "There is no valid $(vref(labels)) for this template."
    elseif length(valids) == 1
        "The only valid $(vref(labels)) for this template is $(first(valids))."
    else
        max = isnothing(labels) ? (template isa AbstractVector ? 100 : 50) : 10
        "Valid $(vrefs(labels)) for this template \
         are $(join_elided(valids, ", ", " and "; max))."
    end
end
valid_refs_phrase(_, template::AbstractMatrix, ::Any) =
    "Valid indices must comply to the following template:\n\
     $(repr(MIME("text/plain"), template))"
vref(::Nothing) = "index"
vrefs(::Nothing) = "indices"
vref(::Any) = "label"
vrefs(::Any) = "labels"
valid_refs(_, template::AbstractSparseVector, ::Nothing) = findnz(template)[1]
valid_refs(_, template::AbstractSparseMatrix, ::Nothing) = zip(findnz(template)[1:2]...)
function valid_refs(v, template::AbstractVector, ::Any)
    valids = Set(valid_refs(v, template, nothing))
    (l for (l, i) in v._index if i in valids)
end


#-------------------------------------------------------------------------------------------
# Convert labels to indexes (a mapping is available as `._index`).

function to_index(v::EitherNodes, s::Label)
    if !hasfield(typeof(v), :_index)
        item = item_name(v)
        throw(ViewError(typeof(v), "No index to interpret $item node label $(repr(s))."))
    end
    map = v._index
    y = Symbol(s)
    if !haskey(map, y)
        item = item_name(v)
        throw(ViewError(
            typeof(v),
            "Invalid $item node label. \
             Expected $(either(keys(map))), \
             got instead: $(repr(s)).",
        ))
    end
    i = map[y]
    (i,)
end

function to_index(v::EitherEdges, s::Label, t::Label)
    verr(mess) = throw(ViewError(typeof(v), mess))
    rows, cols = (v._row_index, v._col_index)
    y = Symbol(s)
    z = Symbol(t)
    if !haskey(rows, y)
        rows = sort(collect(keys(rows)))
        item = item_name(v)
        verr("Invalid $item edge source label: $(repr(y)). \
              Expected $(either(rows)), got instead: $(repr(s)).")
    end
    if !haskey(cols, z)
        cols = sort(collect(keys(cols)))
        item = item_name(v)
        verr("Invalid $item edge target label: $(repr(z)). \
              Expected $(either(cols)), got instead: $(repr(t)).")
    end
    i = rows[y]
    j = cols[z]
    (i, j)
end

either(symbols) =
    length(symbols) == 1 ? "$(repr(first(symbols)))" :
    "either " * join_elided(symbols, ", ", " or ")

# Accessing with the wrong number of dimensions.
function dimerr(reftype, v, level, exp, labs)
    n = length(labs)
    throw(
        ViewError(
            typeof(v),
            "$level data are $exp-dimensional: \
             cannot access $(item_name(v)) data values with $n $(reftype(n)): \
             $(inline(labs)).",
        ),
    )
end
laberr(args...) = dimerr(n -> n > 1 ? "labels" : "label", args...)
inderr(args...) = dimerr(n -> n > 1 ? "indices" : "index", args...)
check_access_dim(v::EitherNodes) = inderr(v, "Nodes", 1, ())
check_access_dim(v::EitherEdges) = inderr(v, "Edges", 2, ())
check_access_dim(v::EitherNodes, i::Int...) = inderr(v, "Nodes", 1, i)
check_access_dim(v::EitherEdges, i::Int...) = inderr(v, "Edges", 2, i)
check_access_dim(::EitherNodes, ::Int) = nothing
check_access_dim(::EitherEdges, ::Int, ::Int) = nothing
check_access_dim(v::EitherNodes, labels::Label...) = laberr(v, "Nodes", 1, labels)
check_access_dim(v::EitherEdges, labels::Label...) = laberr(v, "Edges", 2, labels)
check_access_dim(::EitherNodes, ::Label) = nothing
check_access_dim(::EitherEdges, ::Label, ::Label) = nothing
# Requesting vector[1, 1, 1, 1] is actually valid in julia.
# Only trigger the error out of this very strict 1-situation.
check_access_dim(v::EitherNodes, i::Int, index::Int...) =
    all(==(1), index) || inderr(v, "Nodes", 1, (i, index...))
check_access_dim(v::EitherEdges, i::Int, j::Int, index::Int...) =
    all(==(1), index) || inderr(v, "Edges", 2, (i, j, index...))

# Accessing non-indexed views with labels.
no_labels(v::EitherNodes, s::Label) = throw(
    ViewError(typeof(v), "No index to interpret $(item_name(v)) node label $(repr(s))."),
)
no_labels(v::EitherEdges, s::Label, t::Label) = throw(
    ViewError(
        typeof(v),
        "No index to interpret $(item_name(v)) edge labels $(repr.((s, t))).",
    ),
)

# ==========================================================================================
# Display.

# TODO: any way to avoid the intermediate allocation?
function Base.show(io::IO, ::MIME"text/plain", v::AbstractSparseGraphDataView)
    orig = repr(MIME("text/plain"), v._ref)
    replace(io, orig, repr(typeof(v._ref)) => repr(typeof(v)))
end
function Base.show(io::IO, v::AbstractSparseGraphDataView)
    orig = repr(v._ref)
    replace(io, orig, "sparse" => repr(typeof(v)))
end

end

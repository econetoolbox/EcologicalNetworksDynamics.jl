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
import ..join_elided

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

# Either 1D (for nodes data) or 2D (for edges data).
const AbstractNodesView{T} = AbstractGraphDataView{T,1}
const AbstractEdgesView{T} = AbstractGraphDataView{T,2}

# Read-only or read/write versions (orthogonal to the above)
abstract type AbstractGraphDataReadOnlyView{T,N} <: AbstractGraphDataView{T,N} end
abstract type AbstractGraphDataReadWriteView{T,N} <: AbstractGraphDataView{T,N} end

# Cartesian product of the above two pairs.
# TODO: split again between sparse and dense, to get better display.
abstract type NodesView{T} <: AbstractGraphDataReadOnlyView{T,1} end
abstract type NodesWriteView{T} <: AbstractGraphDataReadWriteView{T,1} end
abstract type EdgesView{T} <: AbstractGraphDataReadOnlyView{T,2} end
abstract type EdgesWriteView{T} <: AbstractGraphDataReadWriteView{T,2} end
export NodesView
export NodesWriteView
export EdgesView
export EdgesWriteView

# ==========================================================================================
# Defer base implementation to the ._ref field.

Base.size(v::AbstractGraphDataView) = size(v._ref)
SparseArrays.findnz(m::AbstractGraphDataView) = findnz(m._ref)
Base.:(==)(a::AbstractGraphDataView, b::AbstractGraphDataView) = a._ref == b._ref

# ==========================================================================================
# Checked access.

# Always valid for reading with indices (or we break AbstractArray contract).
function Base.getindex(v::AbstractGraphDataView, index::Int...)
    check_access_dim(v, index...)
    check_dense_access(v, nothing, index) # Always do to harmonize error messages.
    getindex(v._ref, index...)
end

# Always checked for labelled access.
function Base.getindex(v::AbstractGraphDataView, access::Label...)
    check_access_dim(v, access...)
    index = to_checked_index(v, access...)
    getindex(v._ref, index...)
end
Base.getindex(v::AbstractGraphDataView) = check_access_dim(v) # (trigger correct error)

# Only allow writes for writeable views.
Base.setindex!(v::AbstractGraphDataReadWriteView, rhs, access::Ref...) =
    setindex!(v, rhs, access)
Base.setindex!(v::AbstractGraphDataReadOnlyView, args...) =
    throw(ViewError(typeof(v), "This view into graph $(level_name(v))s data is read-only."))

function setindex!(v::AbstractGraphDataReadWriteView, rhs, access)
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

function to_checked_index(v::AbstractGraphDataView, index::Int...)
    check_access(v, nothing, index)
    index
end

function to_checked_index(v::AbstractGraphDataView, labels::Label...)
    index = to_index(v, labels...)
    check_access(v, labels, index)
    index
end

# Extension points for implementors.
check_access(v::AbstractGraphDataView, _...) = throw("Unimplemented for $(typeof(v)).")
check_label(v::AbstractGraphDataView, _...) = throw("Unimplemented for $(typeof(v)).")

# Check the value to be written prior to underlying call to `Base.setindex!`,
# and take this opportunity to possibly update other values within model besides ._ref.
# Returns the actual value to be passed to `setindex!`.
write!(::Internal, T::Type{<:NodesWriteView}, rhs, index) = rhs

# Name of the thing indexed, useful to improve errors.
item_name(::Type{<:AbstractGraphDataView}) = "item"
item_name(v::AbstractGraphDataView) = item_name(typeof(v))

level_name(::Type{<:AbstractNodesView}) = "node"
level_name(::Type{<:AbstractEdgesView}) = "edge"
level_name(v::AbstractGraphDataView) = level_name(typeof(v))

# ==========================================================================================
# All possible variants of additional index checking in implementors.

#-------------------------------------------------------------------------------------------
# Basic bound checks for dense views.

function check_dense_access(v::AbstractGraphDataView, ::Any, index::Tuple{Vararg{Int}})
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
    v::AbstractGraphDataView,
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
valid_refs(_, template::AbstractVector, ::Nothing) = findnz(template)[1]
valid_refs(_, template::AbstractMatrix, ::Nothing) = zip(findnz(template)[1:2]...)
function valid_refs(v, template::AbstractVector, ::Any)
    valids = Set(valid_refs(v, template, nothing))
    (l for (l, i) in v._index if i in valids)
end


#-------------------------------------------------------------------------------------------
# Convert labels to indexes (a mapping is available as `._index`).

function to_index(v::AbstractNodesView, s::Label)
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

function to_index(v::AbstractEdgesView, s::Label, t::Label)
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
check_access_dim(v::AbstractNodesView) = inderr(v, "Nodes", 1, ())
check_access_dim(v::AbstractEdgesView) = inderr(v, "Edges", 2, ())
check_access_dim(v::AbstractNodesView, i::Int...) = inderr(v, "Nodes", 1, i)
check_access_dim(v::AbstractEdgesView, i::Int...) = inderr(v, "Edges", 2, i)
check_access_dim(::AbstractNodesView, ::Int) = nothing
check_access_dim(::AbstractEdgesView, ::Int, ::Int) = nothing
check_access_dim(v::AbstractNodesView, labels::Label...) = laberr(v, "Nodes", 1, labels)
check_access_dim(v::AbstractEdgesView, labels::Label...) = laberr(v, "Edges", 2, labels)
check_access_dim(::AbstractNodesView, ::Label) = nothing
check_access_dim(::AbstractEdgesView, ::Label, ::Label) = nothing
# Requesting vector[1, 1, 1, 1] is actuall valid in julia.
# Only trigger the error out of this very strict 1-situation.
check_access_dim(v::AbstractNodesView, i::Int, index::Int...) =
    all(==(1), index) || inderr(v, "Nodes", 1, (i, index...))
check_access_dim(v::AbstractEdgesView, i::Int, j::Int, index::Int...) =
    all(==(1), index) || inderr(v, "Edges", 2, (i, j, index...))

# Accessing non-indexed views with labels.
no_labels(v::AbstractNodesView, s::Label) = throw(
    ViewError(typeof(v), "No index to interpret $(item_name(v)) node label $(repr(s))."),
)
no_labels(v::AbstractEdgesView, s::Label, t::Label) = throw(
    ViewError(
        typeof(v),
        "No index to interpret $(item_name(v)) edge labels $(repr.((s, t))).",
    ),
)

end

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

import ..InnerParms

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
ULabel = Union{Symbol,Char,AbstractString}
# Abstract over either index or labels.
UIndex = Union{Int,ULabel}

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

# Assuming the cache has already been updated,
# update the rest of the wrapped _graph.
write!(::InnerParms, ::Type{<:NodesWriteView}, rhs, i) = nothing
write!(::InnerParms, ::Type{<:EdgesWriteView}, rhs, i, j) = nothing

# ==========================================================================================
# Defer base implementation to the ._ref field.

Base.size(v::AbstractGraphDataView) = size(v._ref)

# Checked access.
# Always valid for reading with indices (or we break AbstractArray contract).
Base.getindex(v::AbstractGraphDataView{T,1}, i::Int) where {T} = getindex(v._ref, i)
function Base.getindex(v::AbstractGraphDataView{T,2}, i::Int, j::Int) where {T}
    getindex(v._ref, i, j)
end

# Always checked for labelled access.
function Base.getindex(v::AbstractGraphDataView{T,1}, s::ULabel) where {T}
    i = check_label(s, v)
    getindex(v._ref, i)
end
function Base.getindex(v::AbstractGraphDataView{T,2}, s::ULabel, t::ULabel) where {T}
    i, j = check_label(s, t, v)
    getindex(v._ref, i, j)
end

# Only allow writes for writeable views, and ask for additional logic to the implementor.
function Base.setindex!(v::NodesWriteView, rhs, i::Int)
    i = check_index(i, v)
    setindex!(v._ref, rhs, i)
    write!(v._graph, typeof(v), rhs, i)
end
function Base.setindex!(v::EdgesWriteView, rhs, i::Int, j::Int)
    i, j = check_index(i, j, v)
    setindex!(v._ref, rhs, i, j)
    write!(v._graph, typeof(v), rhs, i, j)
end

# Same with additional label checking when required.
function Base.setindex!(v::NodesWriteView, rhs, s::ULabel)
    i = check_label(s, v)
    i = check_index(i, v; label = s)
    setindex!(v._ref, rhs, i)
    write!(v._graph, typeof(v), rhs, i)
end
function Base.setindex!(v::EdgesWriteView, rhs, s::ULabel, t::ULabel)
    i, j = check_label(s, t, v)
    i, j = check_index(i, j, v; i_label = s, j_label = t)
    setindex!(v._ref, rhs, i, j)
    write!(v._graph, typeof(v), rhs, i, j)
end

# Stub for implementors overload.
check_index(i, v::AbstractGraphDataView; kwargs...) =
    throw("Unimplemented for $(typeof(v)).")
check_index(i, j, v::AbstractGraphDataView; kwargs...) =
    throw("Unimplemented for $(typeof(v)).")
check_label(s, v::AbstractGraphDataView) = throw("Unimplemented for $(typeof(v)).")
check_label(s, t, v::AbstractGraphDataView) = throw("Unimplemented for $(typeof(v)).")

# Forbid writing into read-only views.
Base.setindex!(v::NodesView, rhs, i) =
    throw(ViewError(typeof(v), "This view into graph nodes data is read-only."))
Base.setindex!(v::EdgesView, rhs, i, j) =
    throw(ViewError(typeof(v), "This view into graph edges data is read-only."))

SparseArrays.findnz(m::AbstractEdgesView) = findnz(m._ref)

# ==========================================================================================
# All possible variants of additional index checking in implementors.

#-------------------------------------------------------------------------------------------
# Basic bound checks for dense views.

function check_index_dense_nodes(
    i::Int,
    v::AbstractNodesView,
    item; # Name of the thing indexed, useful to improve errors.
    label::Option{ULabel} = nothing, # Remember original input if label.
)
    verr(mess) = throw(ViewError(typeof(v), mess))
    n = length(v)
    if !(0 < i <= n)
        item = uppercasefirst(item)
        label = isnothing(label) ? "" : " ($(repr(label)))"
        verr("$item index '$i'$label is off-bounds \
              for a view into $n nodes data.")
    end
    i
end
function check_index_dense_edges(
    i::Int,
    j::Int,
    v::AbstractEdgesView,
    item;
    i_label::Option{ULabel} = nothing,
    j_label::Option{ULabel} = nothing,
)
    verr(mess) = throw(ViewError(typeof(v), mess))
    n, m = size(v._ref)
    if !(0 < i <= n && 0 < j <= m)
        item = uppercasefirst(item)
        labels = isnothing(i_label) ? "" : " (($(repr(i_label)), $(repr(j_label))))"
        verr("$item index ($i, $j)$labels is off-bounds \
              for a view into ($n, $m) edges data.")
    end
    (i, j)
end

#-------------------------------------------------------------------------------------------
# For sparse views (a template is available as `._template`).

# Nodes.
function check_index_sparse_nodes(
    i::Int,
    v::AbstractNodesView,
    item; # Name the thing being indexed to improve errors.
    label::Option{ULabel} = nothing, # Set if originally parsed from a label.
)
    check_index_dense_nodes(i, v, item; label)

    verr(mess) = throw(ViewError(typeof(v), mess))
    tp = v._template
    if !tp[i]
        valids = findnz(tp)[1]
        if isnothing(label)
            verr("Invalid $item index '$i' to write data. \
                  Valid indices are:\n  $valids")
        else
            # Then there must be an index.
            valids = Set(valids)
            # Reorder labels because the index is not necessarily ordered.
            labels = [(i, l) for (l, i) in v._index if i in valids]
            sort!(labels)
            labels = last.(labels)
            verr("Invalid $item label '$label' to write data. \
                  Valid labels are:\n  $labels")
        end
    end
    i
end

# Edges.
function check_index_sparse_edges(
    i::Int,
    j::Int,
    v::AbstractEdgesView,
    item;
    i_label::Option{ULabel} = nothing,
    j_label::Option{ULabel} = nothing,
)
    check_index_dense_edges(i, j, v, item; i_label, j_label)

    verr(mess) = throw(ViewError(typeof(v), mess))
    tp = v._template
    if !tp[i, j]
        labels = isnothing(i_label) ? "" : " ($(repr(i_label)), $(repr(j_label)))"
        verr("Invalid $item index $((i, j))$labels to write data. \
              Valid indices are:\n  $([ij for ij in zip(findnz(tp)[1:2]...)])")
    end
    (i, j)
end

#-------------------------------------------------------------------------------------------
# Convert labels to indexes (a mapping is available as `._index`).

function check_label_nodes(s::ULabel, v::AbstractNodesView, item)
    verr(mess) = throw(ViewError(typeof(v), mess))
    map = v._index
    y = Symbol(s)
    if !haskey(map, y)
        verr("Invalid $item node label. \
              Expected $(either(keys(map))), got instead: $(repr(s)).")
    end
    i = map[y]
    i
end

function check_label_edges(s::ULabel, t::ULabel, v::AbstractEdgesView, item)
    verr(mess) = throw(ViewError(typeof(v), mess))
    rows, cols = (v._row_index, v._col_index)
    y = Symbol(s)
    z = Symbol(t)
    if !haskey(rows, y)
        rows = sort(collect(keys(rows)))
        verr("Invalid $item edge source label: $(repr(y)). \
              Expected $(either(rows)), got instead: $(repr(s)).")
    end
    if !haskey(cols, z)
        cols = sort(collect(keys(cols)))
        verr("Invalid $item edge target label: $(repr(z)). \
              Expected $(either(cols)), got instead: $(repr(t)).")
    end
    i = rows[y]
    j = cols[z]
    (i, j)
end

either(symbols) =
    length(symbols) == 1 ? "$(repr(first(symbols)))" :
    "either " * join(repr.(symbols), ", ", " or ")

# Error on accessing non-indexed views with labels.
no_labels_nodes(s::ULabel, v::AbstractNodesView, item) =
    throw(ViewError(typeof(v), "No index to interpret $item node label $(repr(s))."))
no_labels_edges(s::ULabel, t::ULabel, v::AbstractEdgesView, item) =
    throw(ViewError(typeof(v), "No index to interpret $item edge labels $(repr.((s, t)))."))

end

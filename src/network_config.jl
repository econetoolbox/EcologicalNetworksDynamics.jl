# Prior to defining views and components,
# take height to list here all behaviours
# that depend on particular classes/webs/fields.
# Specialize them in the next.

# XXX does this predate GraphDataInputs.convert etc.?

# ==========================================================================================
"""
Dispatch extension point to particular class fields.
"""
struct NodeData{class,field} end
NodeData(class, field) = NodeData{class,field}()
data(::NodeData{class,field}) where {class,field} = (class, field)
class(nd::NodeData) = first(data(nd))
field(nd::NodeData) = last(data(nd))

"""
Check and convert a node data point prior to mutating within the model.
Raise `valerr("simple message")` in case checking fails to obtain contextualized error.
"""
check_value(::NodeData, ::Model, value, ref) = value

# Each ref kind defaults to calling the other one.
# HERE: the default will loop :( Any way out?
function check_value(nd::NodeData, m::Model, x, i::Int)
    idx = N.index(m, class(nd))
    label = to_label(idx, i)
    check_value(nd, m, x, label)
end
function check_value(nd::NodeData, m::Model, x, l::Symbol)
    idx = N.index(m, class(nd))
    i = to_index(idx, l)
    check_value(nd, m, x, i)
end

"""
Check and convert all class data prior to creating it within the model.
"""
function check_values(nd::NodeData, model::Model, values)
    # Default to checking all values one by one.
    (class, _) = data(nd)
    n = n_nodes(model, class)
    l = length(values)
    n == l || throw(SizeError(n, l))
    labels = node_labels(model, class(nd))
    for (label, value) in zip(labels, values)
        check_value(nd, model, value, label)
    end
end

struct ValueError <: Exception
    mess::String
end
valerr(m, throw = throw) = throw(ValueError(m))

struct SizeError <: Exception
    expected::Int
    actual::Int
end

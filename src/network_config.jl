# Prior to defining views and components,
# take height to list here all behaviours
# that depend on particular classes/webs/fields.
# Specialize them in the next.

# XXX does this predate GraphDataInputs.convert etc.?

module NetworkConfig

using EcologicalNetworksDynamics: Networks, Model
using .Networks

const Ref = Union{Int,Symbol}

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
Check and convert a node data point without information about the rest of the model.
Useful within `Framework.early_check`.
Raise `valerr("simple message")` in case checking fails to obtain contextualized error.
"""
check_value(::NodeData, value) = value

"""
Check and convert a node data point with knowledge about the rest of the model.
Useful prior to mutating within the model.
Raise `valerr("simple message")` in case checking fails to obtain contextualized error.
"""
# TODO: Could these receive only 1 generic ref type and not both?
# https://julialang.zulipchat.com/#narrow/channel/137791-general/topic/Dispatch.20struggle.20with.20default.20conversions.2Fimplementations.2E/with/573461702
check_value(nd::NodeData, ::Model, value, ::Symbol, ::Int) = check_value(nd, value)

# If providing only one ref, automatically convert to the other one.
function check_value(nd::NodeData, m::Model, x, r::Ref)
    (i, l) = both_refs(r)
    check_value(nd, m, x, l, i)
end
function both_refs(nd::NodeData, m::Model, i::Int)
    idx = N.index(m, class(nd))
    l = to_label(idx, i)
    (l, i)
end
function both_refs(nd::NodeData, m::Model, l::Symbol)
    idx = N.index(m, class(nd))
    i = to_index(idx, l)
    (l, i)
end

"""
Default extension to all values.
Useful within `Framework.late_check`.
"""
function check_values(nd::NodeData, values)
    # Default to checking every value individually.
    map(enumerate(values)) do (i, value)
        try
            check_value(nd, value)
        catch e
            e isa ValueError &&
                valerr("Incorrect value at index [$i]:\n$(e.message)", rethrow)
            rethrow(e)
        end
    end
end

"""
Check and convert all class data prior to creating it within the model.
Useful within `Framework.late_check`.
"""
function check_values(nd::NodeData, model::Model, values)
    # Default to checking all values one by one.
    (class, _) = data(nd)
    n = n_nodes(model, class)
    l = length(values)
    n == l || throw(SizeError(n, l))
    labels = node_labels(model, class(nd))
    for (i, (label, value)) in enumerate(zip(labels, values))
        check_value(nd, model, value, label, i)
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
end

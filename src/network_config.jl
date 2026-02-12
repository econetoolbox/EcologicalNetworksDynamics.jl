# Prior to defining views and components,
# take height to list here all behaviours
# that depend on particular classes/webs/data.
# Specialize them in the next.
# In other terms, every statically consistent variable information
# we have about classes/webs/data exposed by the package
# can be expressed as specialization of the methods defined here.

# XXX does this predate GraphDataInputs.convert etc.?

module NetworkConfig

using EcologicalNetworksDynamics: Networks, Model
using .Networks
const N = Networks

const Ref = Union{Int,Symbol}

# ==========================================================================================
# Class.

"""
Dispatch to a particular class.
"""
struct NodeClass{class} end
NodeClass(class::Symbol) = NodeClass{class}()
N.class(::NodeClass{class}) where {class} = class
export NodeClass

"""
Obtain name variants for nodes in the class, in order:

  - short `p_`refix
  - snake_case singular
  - snake_case plural
  - CamelCase singular
  - CamelCase plural
"""
name_variants(::NodeClass) = throw("unimplemented")
short_prefix(nc::NodeClass) = name_variants(nc)[1]
snake_case_singular(nc::NodeClass) = name_variants(nc)[2]
snake_case_plural(nc::NodeClass) = name_variants(nc)[3]
CamelCaseSingular(nc::NodeClass) = name_variants(nc)[4]
CamelCasePlural(nc::NodeClass) = name_variants(nc)[5]
export name_variants,
    short_prefix, snake_case_singular, snake_case_plural, CamelCaseSingular, CamelCasePlural

"""
Obtain the component providing the class.
"""
component(::NodeClass) = throw("unimplemented")
export component

# ==========================================================================================
# Web.

"""
Dispatch to a particular web.
"""
struct EdgeWeb{web} end
EdgeWeb(web::Symbol) = EdgeWeb{web}()
N.web(::EdgeWeb{web}) where {web} = web
export EdgeWeb

"""
Obtain name variants for the web, in order:

  - snake_case
  - CamelCase
"""
name_variants(::EdgeWeb) = throw("unimplemented")
snake_case(ew::EdgeWeb) = name_variants(ew)[1]
CamelCase(ew::EdgeWeb) = name_variants(ew)[2]
export snake_case, CamelCase

"""
Property name, if different from the web name.
"""
propnames(ew::EdgeWeb) = (snake_case(ew), CamelCase(ew))
export propnames

"""
Obtain the component providing the web.
"""
component(::EdgeWeb) = throw("unimplemented")

"""
Names of the (source, target) classes.
"""
sidenames(::EdgeWeb) = throw("unimplemented")
sourcename(ew::EdgeWeb) = first(sidenames(ew))
targetname(ew::EdgeWeb) = last(sidenames(ew))
export sidenames, sourcename, targetname

"""
Obtain dispatchers to the source/target classes.
"""
sides(ew::EdgeWeb) = NodeClass.(sidenames(ew))
source(ew::EdgeWeb) = NodeClass(sourcename(ew))
target(ew::EdgeWeb) = NodeClass(targetname(ew))
export sides, source, target

"""
Raise for reflexive webs.
"""
is_reflexive(::EdgeWeb) = throw("unimplemented")
export is_reflexive

# ==========================================================================================
# Node data.

"""
Dispatch extension point to particular class data.
"""
struct NodeData{class,data} end
NodeData(class::Symbol, data::Symbol) = NodeData{class,data}()
content(::NodeData{class,data}) where {class,data} = (class, data)
N.class(nd::NodeData) = first(data(nd))
data(nd::NodeData) = last(data(nd))
readonly(::NodeData) = false # By default, or specialize.
export NodeData, content, data, readonly

"""
Obtain name variants for the data points, in order:

  - snake_case singular
  - snake_case plural
"""
name_variants(::NodeData) = throw("unimplemented")
snake_case_singular(nd::NodeData) = name_variants(nd)[1]
snake_case_plural(nd::NodeData) = name_variants(nd)[2]

"""
Check and convert a node data point without information about the rest of the model.
Useful within `Framework.early_check`.
Raise `valerr("simple message")` in case checking fails to obtain contextualized error.
"""
check_value(::NodeData, value) = value
export check_value

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

struct ValueError <: Exception
    mess::String
end
valerr(m, throw = throw) = throw(ValueError(m))
export ValueError, valerr

# ==========================================================================================
# Display.

function Base.show(io::IO, nd::NodeData)
    class, data = content(nd)
    print(io, "<$class:$data>")
end

end

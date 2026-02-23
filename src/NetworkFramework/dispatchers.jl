"""
Typical components have most of their behaviour defined generically,
except for some configurable details whose extension points are defined in this module.
Phantom data types defined here are parametrized with particular class/web/field names.
The purpose is that component authors may refine components behaviour
by specializing implementations for their particular component.
"""
module Dispatchers

using EcologicalNetworksDynamics: Networks
using .Networks
const N = Networks
const D = Dispatchers

const Option{T} = Union{Nothing,T}
const Ref = Union{Int,Symbol}

abstract type Dispatcher end
export Dispatcher

# ==========================================================================================
# Class.

"""
Dispatch to a particular class.
"""
struct NodeClass{class} <: Dispatcher end
export NodeClass
NodeClass(class::Symbol) = NodeClass{class}()
S = NodeClass # 'Self'
class(::S{class}) where {class} = class

"""
Obtain name variants for nodes in the class, in order:

  - short `p_`refix
  - snake_case singular
  - snake_case plural
  - CamelCase singular
  - CamelCase plural
"""
name_variants(::S) = throw("unimplemented")
short_prefix(s::S) = name_variants(s)[1]
snake_case_singular(s::S) = name_variants(s)[2]
snake_case_plural(s::S) = name_variants(s)[3]
CamelCaseSingular(s::S) = name_variants(s)[4]
CamelCasePlural(s::S) = name_variants(s)[5]

"""
Obtain the component providing the class.
"""
component(::S) = throw("unimplemented")

# Display.
function Base.show(io::IO, s::S)
    class = D.class(s)
    print(io, "<$class>")
end

# ==========================================================================================
# Node mask.

"""
Dispatch to a particular class from the perspective of a parent class.
"""
struct NodeMask{class,parent} <: Dispatcher end
export NodeMask
NodeMask(class::Symbol, parent::Option{Symbol}) = NodeMask{class,parent}()
S = NodeMask
content(::S{class,parent}) where {class,parent} = (class, parent)
class(s::S) = first(content(s))
parent(s::S) = last(content(s))

"""
Obtain dispatcher to underlying class.
"""
NodeClass(s::S) = NodeClass(class(s))

# Display.
function Base.show(io::IO, s::S)
    class, parent = content(s)
    print(io, "<$parent:$class>")
end

# ==========================================================================================
# Web.

"""
Dispatch to a particular web.
"""
struct EdgeWeb{web} <: Dispatcher end
export EdgeWeb
EdgeWeb(web::Symbol) = EdgeWeb{web}()
S = EdgeWeb # 'Self'
web(::S{web}) where {web} = web

"""
Obtain name variants for the web, in order:

  - snake_case
  - CamelCase
"""
name_variants(::S) = throw("unimplemented")
snake_case(s::S) = name_variants(s)[1]
CamelCase(s::S) = name_variants(s)[2]

"""
Property name, if different from the web name.
"""
propnames(s::S) = (snake_case(s), CamelCase(s))

"""
Obtain the component providing the web.
"""
component(::S) = throw("unimplemented")

"""
Names of the (source, target) classes.
"""
sidenames(::S) = throw("unimplemented")
sourcename(s::S) = first(sidenames(s))
targetname(s::S) = last(sidenames(s))

"""
Obtain dispatchers to the source/target classes.
"""
sides(s::S) = NodeClass.(sidenames(s))
source(s::S) = NodeClass(sourcename(s))
target(s::S) = NodeClass(targetname(s))

"""
Raise for reflexive webs.
"""
is_reflexive(::S) = throw("unimplemented")

# Display.
function Base.show(io::IO, s::S)
    web = D.web(s)
    print(io, "<$web>")
end

# ==========================================================================================
# Node data.

"""
Dispatch extension point to particular class data.
"""
struct NodeData{class,data} <: Dispatcher end
export NodeData
NodeData(class::Symbol, data::Symbol) = NodeData{class,data}()
S = NodeData # 'Self'
content(::S{class,data}) where {class,data} = (class, data)
class(s::S) = first(data(s))
data(s::S) = last(data(s))
readonly(::S) = false # By default, or specialize.
type(::S) = throw("unimplemented") # Underlying data type.

"""
Obtain name variants for the data points, in order:

  - snake_case singular
  - snake_case plural
"""
name_variants(::S) = throw("unimplemented")
snake_case_singular(s::S) = name_variants(s)[1]
snake_case_plural(s::S) = name_variants(s)[2]

"""
Obtain dispatcher to underlying class.
"""
NodeClass(s::S) = NodeClass(class(s))

# Display.
function Base.show(io::IO, s::S)
    class, data = content(s)
    print(io, "<$class:$data>")
end

# ==========================================================================================
# Expanded node data.

"""
Dispatch extension point to particular class data
from the perspective of a parent class.
"""
struct ExpandedNodeData{class,data,parent} <: Dispatcher end
export ExpandedNodeData
ExpandedNodeData(class::Symbol, data::Symbol, parent::Option{Symbol}) =
    ExpandedNodeData{class,data,parent}()
S = ExpandedNodeData # 'Self'
content(::S{class,data,parent}) where {class,data,parent} = (class, data, parent)
class(s::S) = first(content(s))
data(s::S) = content(s)[2]
parent(s::S) = last(content(s))
type(::S) = throw("unimplemented")

"""
Obtain dispatchers to underlying class, mask, data.
"""
NodeClass(s::S) = NodeClass(class(s))
NodeMask(s::S) = NodeMask(class(s), parent(s))
NodeData(s::S) = NodeData(class(s), data(s))

# Display.
function Base.show(io::IO, s::S)
    class, data, parent = content(s)
    print(io, "<$parent:$class:$data>")
end

# ==========================================================================================
# Web data.

"""
Dispatch extension point to particular web data.
"""
struct EdgeData{web,data} <: Dispatcher end
export EdgeData
EdgeData(web::Symbol, data::Symbol) = EdgeData{web,data}()
S = EdgeData # 'Self'
content(::S{web,data}) where {web,data} = (web, data)
N.web(s::S) = first(data(s))
data(s::S) = last(data(s))

"""
Obtain dispatcher to underlying web.
"""
EdgeWeb(s::S) = EdgeWeb(web(s))

# Display.
function Base.show(io::IO, s::S)
    web, data = content(s)
    print(io, "<$web:$data>")
end

end

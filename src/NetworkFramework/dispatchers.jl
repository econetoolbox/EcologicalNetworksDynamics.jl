"""
Typical components have most of their behaviour defined generically,
except for some configurable details whose extension points are defined in this module.
Phantom data types defined here are parametrized with particular class/web/field names.
The purpose is that component authors may refine components behaviour
by specializing implementations for their particular component.
"""
module Dispatchers

using EcologicalNetworksDynamics: N, Networks, Display
using .Display: cyan, reset
const D = Dispatchers

const Option{T} = Union{Nothing,T}
const Ref = Union{Int,Symbol}

"For convenience, initial constructors (from symbols) return both instance and type."
abstract type Dispatcher end

# ==========================================================================================
# Class.

"""
Dispatch to a particular class.
"""
struct Class{class} <: Dispatcher end
function Class(class::Symbol)
    T = Class{class}
    T(), T
end
S = Class # 'Self'
class(::S{cl}) where {cl} = cl

"""
Obtain name variants for nodes in the class, in order:

  - short `p_`refix
  - snake_case_singular
  - snake_case_plural
  - CamelCaseSingular
  - CamelCasePlural
"""
name_variants(s::S) = throw("Name variants unspecified for $s.")
short_prefix(s::S) = name_variants(s)[1]
snake_case_singular(s::S) = name_variants(s)[2]
snake_case_plural(s::S) = name_variants(s)[3]
CamelCaseSingular(s::S) = name_variants(s)[4]
CamelCasePlural(s::S) = name_variants(s)[5]

"""
Obtain the component providing the class.
"""
component(s::S) = throw("Component unspeficied for $s.")

# Display.
function Base.show(io::IO, s::S)
    class = D.class(s)
    print(io, "$cyan<$class>$reset")
end

# ==========================================================================================
# Node mask.

"""
Dispatch to a particular class from the perspective of a parent class.
"""
struct Subclass{class,parent} <: Dispatcher end
function Subclass(class::Symbol, parent::Option{Symbol})
    T = Subclass{class,parent}
    T(), T
end
S = Subclass
content(::S{class,parent}) where {class,parent} = (class, parent)
class(s::S) = first(content(s))
parent(s::S) = last(content(s))

"""
Obtain dispatcher to underlying class.
"""
Class(s::S) = Class(class(s))

# Display.
function Base.show(io::IO, s::S)
    class, parent = content(s)
    print(io, "$cyan<$parent:$class>$reset")
end

# ==========================================================================================
# Web.

"""
Dispatch to a particular web.
"""
struct Web{web} <: Dispatcher end
function Web(web::Symbol)
    T = Web{web}
    T(), T
end
S = Web # 'Self'
web(::S{w}) where {w} = w

# Categorize webs.
is_reflexive(s::S) = source(s) == target(s)
is_symmetric(s::S) =
    is_reflexive(s) ? throw("Unspecified whether $s reflexive web topology is symmetric.") :
    false # No need to implement for non-reflexive webs.
is_sparse(::S) = throw("unimplemented") # Always need to specify.


"""
Obtain name variants for the web, in order:

  - snake_case
  - CamelCase
"""
name_variants(s::S) = throw("Name variants unspecified for $s.")
snake_case(s::S) = name_variants(s)[1]
CamelCase(s::S) = name_variants(s)[2]

"""
Property name, if different from the web name.
"""
propnames(s::S) = (snake_case(s), CamelCase(s))

"""
Obtain the component providing the web.
"""
component(s::S) = throw("Component unspecified for $s.")

"""
Names of the (source, target) classes.
"""
sidenames(s::S) = throw("Source and target classes unspecified for $s.")
sourcename(s::S) = first(sidenames(s))
targetname(s::S) = last(sidenames(s))

"""
Obtain dispatchers to the source/target classes.
"""
sides(s::S) = Class.(sidenames(s))
source(s::S) = Class(sourcename(s))
target(s::S) = Class(targetname(s))

# Display.
function Base.show(io::IO, s::S)
    web = D.web(s)
    print(io, "$cyan<$web>$reset")
end

# TODO: do we need a "Subweb"? Maybe refactor components first to figure this.

# ==========================================================================================
# Graph-level data field.
"""
Dispatch to a particular global network field.
"""
struct GraphField{field} <: Dispatcher end
function GraphField(field::Symbol)
    T = GraphField{field}
    T(), T
end
S = GraphField # 'Self'
content(::S{fd}) where {fd} = (fd,)
field(s::S) = s |> content |> first

"""
Obtain name variants for field data, in order:

  - shortname
  - snake_case_singular
  - CamelCaseSingular
"""
name_variants(s::S) = throw("Name variants unspecified for $s.")
shortname(s::S) = name_variants(s)[1]
snake_case_singular(s::S) = name_variants(s)[2]
CamelCaseSingular(s::S) = name_variants(s)[3]

# Display.
function Base.show(io::IO, s::S)
    field = D.field(s)
    print(io, "$cyan<$field>$reset")
end

# ==========================================================================================
# Node field.

"""
Dispatch extension point to particular class field data.
"""
struct NodeField{class,field} <: Dispatcher end
function NodeField(class::Symbol, field::Symbol)
    T = NodeField{class,field}
    T(), T
end
S = NodeField # 'Self'
content(::S{class,field}) where {class,field} = (class, field)
class(s::S) = first(content(s))
field(s::S) = last(content(s))
type(s::S) = throw("Data type unspecified for $s.") # Underlying data type.

"""
Obtain dispatcher to underlying class.
"""
Class(s::S) = Class(class(s))

# Display.
function Base.show(io::IO, s::S)
    class, field = content(s)
    print(io, "$cyan<$class:$field>$reset")
end

# ==========================================================================================
# Subnode field data, expanded within a parent class.

"""
Dispatch extension point to particular class field data
from the perspective of a parent class.
"""
struct SubnodeField{class,field,parent} <: Dispatcher end
function SubnodeField(class::Symbol, field::Symbol, parent::Option{Symbol})
    T = SubnodeField{class,field,parent}
    T(), T
end
S = SubnodeField # 'Self'
content(::S{class,field,parent}) where {class,field,parent} = (class, field, parent)
class(s::S) = first(content(s))
field(s::S) = content(s)[2]
parent(s::S) = last(content(s))
type(s::S) = throw("Data type unspecified for $s.")

"""
Obtain dispatchers to underlying class, mask, field.
"""
Class(s::S) = Class(class(s))
Subclass(s::S) = Subclass(class(s), parent(s))
NodeField(s::S) = NodeField(class(s), field(s))

# Display.
function Base.show(io::IO, s::S)
    class, field, parent = content(s)
    print(io, "$cyan<$parent:$class:$field>$reset")
end

#-------------------------------------------------------------------------------------------
# Abstract over either node field category.
const AbstractNodeField{class,field} =
    Union{NodeField{class,field},SubnodeField{class,field}}

# ==========================================================================================
# Web field.

"""
Dispatch extension point to particular web field data.
"""
struct EdgeField{web,field} <: Dispatcher end
function EdgeField(web::Symbol, field::Symbol)
    T = EdgeField{web,field}
    T(), T
end
S = EdgeField # 'Self'
content(::S{web,field}) where {web,field} = (web, field)
web(s::S) = first(content(s))
field(s::S) = last(content(s))

"""
Obtain dispatcher to underlying web.
"""
Web(s::S) = Web(web(s))

# Display.
function Base.show(io::IO, s::S)
    web, field = content(s)
    print(io, "$cyan<$web:$field>$reset")
end

# ==========================================================================================
# Abstract over either field category.
const AbstractField{field} =
    Union{GraphField{field},<:AbstractNodeField{<:Any,field},<:EdgeField{<:Any,field}}
S = AbstractField
readonly(::S) = false # By default, or specialize.
viewtype(::S) = throw("unimplemented") # The data view for this field.

"""
Obtain name variants for the data points, in order:

  - snake_case singular
  - snake_case plural
  - CamelCase singular
  - CamelCase plural
  - short field name
"""
name_variants(s::S) = throw("Name variants unspecified for $s.")
snake_case_singular(s::S) = name_variants(s)[1]
snake_case_plural(s::S) = name_variants(s)[2]
CamelCaseSingular(s::S) = name_variants(s)[3]
CamelCasePlural(s::S) = name_variants(s)[4]
short_field_name(s::S) = name_variants(s)[5]

# ==========================================================================================
# Abstract over levels.
const GraphLevel = GraphField
const NodeLevel = Union{Class,Subclass,NodeField,SubnodeField}
const EdgeLevel = Union{Web,EdgeField}
dim(::GraphField) = 0
dim(::NodeLevel) = 1
dim(::EdgeLevel) = 2
level(::GraphField) = "graph"
level(::NodeLevel) = "node"
level(::EdgeLevel) = "edge"

end

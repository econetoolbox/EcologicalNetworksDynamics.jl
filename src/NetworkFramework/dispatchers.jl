"""
Typical components have most of their behaviour defined generically,
except for some configurable details whose extension points are defined in this module.
Phantom data types defined here are parametrized with particular class/web/field names.
The purpose is that component authors may refine components behaviour
by specializing implementations for their particular component.
"""
module Dispatchers

using EcologicalNetworksDynamics: N, Networks
using .Networks
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
class(::S{cl}) where {cl} = cl

"""
Obtain name variants for nodes in the class, in order:

  - short `p_`refix
  - snake_case singular
  - snake_case plural
  - CamelCase singular
  - CamelCase plural
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
web(::S{w}) where {w} = w

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
sides(s::S) = NodeClass.(sidenames(s))
source(s::S) = NodeClass(sourcename(s))
target(s::S) = NodeClass(targetname(s))

"""
Raise for symmetric webs.
"""
is_reflexive(s::S) = source(s) == target(s)
is_symmetric(s::S) =
    is_reflexive(s) ? throw("Unspecified whether $s reflexive web topology is symmetric.") :
    false

# Display.
function Base.show(io::IO, s::S)
    web = D.web(s)
    print(io, "<$web>")
end

# ==========================================================================================
# Node field.

"""
Dispatch extension point to particular class field data.
"""
struct NodeField{class,field} <: Dispatcher end
export NodeField
NodeField(class::Symbol, field::Symbol) = NodeField{class,field}()
S = NodeField # 'Self'
content(::S{class,field}) where {class,field} = (class, field)
class(s::S) = first(content(s))
field(s::S) = last(content(s))
type(s::S) = throw("Data type unspecified for $s.") # Underlying data type.

"""
Obtain dispatcher to underlying class.
"""
NodeClass(s::S) = NodeClass(class(s))

# Display.
function Base.show(io::IO, s::S)
    class, field = content(s)
    print(io, "<$class:$field>")
end

# ==========================================================================================
# Sparse node field data, expanded within a parent class.

"""
Dispatch extension point to particular class field data
from the perspective of a parent class.
"""
struct SparseNodeField{class,field,parent} <: Dispatcher end
export SparseNodeField
SparseNodeField(class::Symbol, field::Symbol, parent::Option{Symbol}) =
    SparseNodeField{class,field,parent}()
S = SparseNodeField # 'Self'
content(::S{class,field,parent}) where {class,field,parent} = (class, field, parent)
class(s::S) = first(content(s))
field(s::S) = content(s)[2]
parent(s::S) = last(content(s))
type(s::S) = throw("Data type unspecified for $s.")

"""
Obtain dispatchers to underlying class, mask, field.
"""
NodeClass(s::S) = NodeClass(class(s))
NodeMask(s::S) = NodeMask(class(s), parent(s))
NodeField(s::S) = NodeField(class(s), field(s))

# Display.
function Base.show(io::IO, s::S)
    class, field, parent = content(s)
    print(io, "<$parent:$class:$field>")
end

#-------------------------------------------------------------------------------------------
# Abstract over either node field category.
const AbstractNodeField{class,field} =
    Union{NodeField{class,field},SparseNodeField{class,field}}
export AbstractNodeField
S = AbstractNodeField
readonly(::S) = false # By default, or specialize.

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
# Web field.

"""
Dispatch extension point to particular web field data.
"""
struct EdgeField{web,field} <: Dispatcher end
export EdgeField
EdgeField(web::Symbol, field::Symbol) = EdgeField{web,field}()
S = EdgeField # 'Self'
content(::S{web,field}) where {web,field} = (web, field)
web(s::S) = first(content(s))
field(s::S) = last(content(s))

"""
Obtain dispatcher to underlying web.
"""
EdgeWeb(s::S) = EdgeWeb(web(s))

# Display.
function Base.show(io::IO, s::S)
    web, field = content(s)
    print(io, "<$web:$field>")
end

end

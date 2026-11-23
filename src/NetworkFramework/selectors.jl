"""
Typical components have most of their behaviour defined generically,
except for some configurable details whose extension points are defined in this module.
Phantom data types defined here are parametrized with particular class/web/field names.
The purpose is that component authors may refine components behaviour
by specializing implementations for their particular component.
"""
module Selectors

using EcologicalNetworksDynamics: ST, Storage, Display, unimplemented, Option
using EcologicalNetworksDynamics.NetworkFramework: Model, Ref
using .Display: cyan, reset

"For convenience, initial constructors (from symbols) return both instance and type."
abstract type Selector end

# ==========================================================================================
# Class.

"Dispatch to a particular class."
struct Class{class} <: Selector end
function Class(c::Symbol)
    T = Class{c}
    T(), T
end
class(c::Symbol) = c |> Class |> first
S = Class # 'Self'
classname(::S{cl}) where {cl} = cl

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

"Obtain the component providing the class."
component(s::S) = throw("Component unspeficied for $s.")

# Display.
function Base.show(io::IO, s::S)
    class = classname(s)
    print(io, "<$class>")
end

# ==========================================================================================
# Node mask.

"Dispatch to a particular class from the perspective of a parent class."
struct Subclass{class,parent} <: Selector end
function Subclass(class::Symbol, parent::Option{Symbol})
    T = Subclass{class,parent}
    T(), T
end
subclass(c::Symbol, p::Option{Symbol}) = Subclass(c, p) |> first
S = Subclass
content(::S{class,parent}) where {class,parent} = (class, parent)
classname(s::S) = first(content(s))
parentname(s::S) = last(content(s))

"Obtain selector to underlying class."
Class(s::S) = s |> classname |> Class

# Display.
function Base.show(io::IO, s::S)
    class, parent = content(s)
    print(io, "<$parent:$class>")
end

# ==========================================================================================
# Web.

"Dispatch to a particular web."
struct Web{web} <: Selector end
function Web(web::Symbol)
    T = Web{web}
    T(), T
end
web(w::Symbol) = w |> Web |> first
S = Web # 'Self'
webname(::S{w}) where {w} = w

# Categorize webs.
is_reflexive(s::S) = source(s) == target(s)
is_symmetric(s::S) =
    is_reflexive(s) ? throw("Unspecified whether $s reflexive web topology is symmetric.") :
    false # No need to implement for non-reflexive webs.
is_sparse(s::S) = unimplemented(is_sparse, s) # Always need to specify.

"""
Obtain name variants for the web, in order:

  - snake_case
  - CamelCase
"""
name_variants(s::S) = throw("Name variants unspecified for $s.")
snake_case(s::S) = name_variants(s)[1]
CamelCase(s::S) = name_variants(s)[2]

"Property name, if different from the web name."
propnames(s::S) = (snake_case(s), CamelCase(s))

"Obtain the component providing the web."
component(s::S) = throw("Component unspecified for $s.")

"Names of the (source, target) classes."
sidenames(s::S) = throw("Source and target classes unspecified for $s.")

# Display.
function Base.show(io::IO, s::S)
    web = webname(s)
    print(io, "<$web>")
end

# ==========================================================================================
# Graph-level data field.
"Dispatch to a particular global network field."
struct GraphField{field} <: Selector end
function GraphField(field::Symbol)
    T = GraphField{field}
    T(), T
end
graphfield(f::Symbol) = f |> GraphField |> first
S = GraphField # 'Self'
content(::S{fd}) where {fd} = (fd,)
fieldname(s::S) = s |> content |> first

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
    field = fieldname(s)
    print(io, "<$field>")
end

# ==========================================================================================
# Node field.

"Dispatch extension point to particular class field data."
struct NodeField{class,field} <: Selector end
function NodeField(class::Symbol, field::Symbol)
    T = NodeField{class,field}
    T(), T
end
nodefield(c::Symbol, f::Symbol) = NodeField(c, f) |> first
S = NodeField # 'Self'
content(::S{class,field}) where {class,field} = (class, field)
classname(s::S) = first(content(s))
fieldname(s::S) = last(content(s))
type(s::S) = throw("Data type unspecified for $s.") # Underlying data type.

"Obtain selector to underlying class."
class(s::S) = s |> classname |> class

# Display.
function Base.show(io::IO, s::S)
    class, field = content(s)
    print(io, "<$class:$field>")
end

# ==========================================================================================
# Web field.

"Dispatch extension point to particular web field data."
struct EdgeField{web,field} <: Selector end
function EdgeField(web::Symbol, field::Symbol)
    T = EdgeField{web,field}
    T(), T
end
edgefield(w::Symbol, f::Symbol) = EdgeField(w, f) |> first
S = EdgeField # 'Self'
content(::S{web,field}) where {web,field} = (web, field)
webname(s::S) = first(content(s))
fieldname(s::S) = last(content(s))

"Obtain selector to underlying web."
web(s::S) = s |> webname |> web

# Delegate.
sidenames(s::S) = s |> web |> sidenames
is_sparse(s::S) = s |> web |> is_sparse
is_dense(s::S) = s |> web |> is_dense

# Display.
function Base.show(io::IO, s::S)
    web, field = content(s)
    print(io, "<$web:$field>")
end

# ==========================================================================================
# Abstract over either field category.
const AbstractField{field} =
    Union{GraphField{field},<:NodeField{<:Any,field},<:EdgeField{<:Any,field}}
S = AbstractField
readonly(::S) = false # By default, or specialize.
viewtype(s::S) = unimplemented(viewtype, s) # The data view for this field.

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
# Abstract over topology-related data.
const Topology = Union{Class,Web}

# ==========================================================================================
# Abstract over levels.
const GraphLevel = GraphField
const NodeLevel = Union{Class,NodeField,Subclass}
const EdgeLevel = Union{Web,EdgeField}
dim(::GraphField) = 0
dim(::NodeLevel) = 1
dim(::EdgeLevel) = 2
level(::GraphField) = "graph"
level(::NodeLevel) = "node"
level(::EdgeLevel) = "edge"

S = EdgeLevel
is_dense(s::S) = !is_sparse(s)
sourcename(s::S) = s |> sidenames |> first
targetname(s::S) = s |> sidenames |> last
sides(s::S) = s |> sidenames .|> class
source(s::S) = s |> sourcename |> class
target(s::S) = s |> targetname |> class

# ==========================================================================================
# Use selector as static index into underlying data.

ST.class(md::Model, s::NodeLevel) = ST.class(ST.network(md), classname(s))
ST.web(md::Model, s::EdgeLevel) = ST.web(ST.network(md), webname(s))
ST.sides(md::Model, s::EdgeLevel) = ST.sides(ST.network(md), webname(s))
ST.source(md::Model, s::EdgeLevel) = ST.source(ST.network(md), webname(s))
ST.target(md::Model, s::EdgeLevel) = ST.target(ST.network(md), webname(s))
ST.entry(md::Model, s::GraphField) = ST.network(md).data[fieldname(s)]
ST.entry(md::Model, s::NodeField) = ST.class(md, s).data[fieldname(s)]
ST.entry(md::Model, s::EdgeField) = ST.web(md, s).data[fieldname(s)]

# TODO: this should resolve statically without a query to `md` :\
ST.is_root(md::Model, s::NodeLevel) = ST.class(md, s) |> ST.is_root

"In this context, root classes admit themselves as their own parents."
function ST.parent(md::Model, s::Subclass)
    p = parentname(s)
    par = isnothing(p) ? classname(s) : p
    ST.class(ST.network(md), par)
end

# Use it to shorten these frequent ones.
ST.to_label(md::Model, s::NodeLevel, i) = ST.to_label(ST.class(md, s).index, i)
ST.to_index(md::Model, s::NodeLevel, a) = ST.to_index(ST.class(md, s).index, a)
ST.to_label(md::Model, s::EdgeLevel, i, j) =
    ST.to_label.(map(cl -> cl.index, ST.sides(md, s)), (i, j))
ST.to_index(md::Model, s::EdgeLevel, a, b) =
    ST.to_index.(map(cl -> cl.index, ST.sides(md, s)), (a, b))
ST.to_ref(R::Type, md::Model, s::Selector, u) = ST.to_ref(R, ST.class(md, s).index, u)
ST.to_ref(R::Type, md::Model, s::Selector, u, v) =
    ST.to_ref.((R,), map(cl -> cl.index, ST.sides(md, s)), (u, v))

# Wide display.
Base.show(io::IO, ::MIME"text/plain", s::Selector) = print(io, "$cyan$s$reset")

end

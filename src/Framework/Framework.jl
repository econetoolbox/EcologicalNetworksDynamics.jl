# This framework is dedicated to wrap a sophisticated value into a 'System'.
#
# Motivation:
#
#   The wrapped value is powerful but complicated
#   and its state needs to be carefully maintained.
#   Lib devs want to expose it to their users so they can enjoy the benefit of it,
#   but they also want to protect them from breaking the internal state.
#
# Instead of exposing the value directly,
# lib devs wrap it into a 'System':
#
#   s = System{WrappedValue}()
#
# And then they carefully develop an associated collection of 'components' and 'methods'.
#
# The whole module can be viewed as an extension of the "builder" pattern.
# Instead of constructing the value directly,
# lib users will start from an "empty" or "default" base system,
# then populate it with the 'components' at hand
# until it contains all the data required to exhibit the behaviour they need
# via the 'methods' at hand.
#
# Consistently with this "builder" approach,
# 'components' are not actual values,
# but rather abstract, diffuse sets of data appended to the protected state.
# In consequence, lib users cannot get a 'component' variable
# referring to data inside the system.
# Instead, they get 'blueprints' for components,
# which they can construct and tweak like regular julia structs.
# When ready, a blueprint can be read by the system, 'check'ed,
# and 'expand'ed into the actual component(s).
#
# No component can be added twice to the same system,
# but blueprints can be read and expanded into different components types.
# Also, the components they 'provide' may depend on their value
# and/or the current state of the system.
#
# 'Components' contain no data and are implemented as julia singletons marker types.
# 'Blueprints' are regular data structures implementing the blueprint interface.
#
# Adding a component to the system therefore reduces to:
#
#   add!(s, blueprint)
#
# And using exposed methods as simple:
#
#   method(s)
#
# Additional sugar is provided:
#
#   s = System{WrappedValue}(blueprints...) # Start from a sequence of initial blueprints.
#   s += blueprint                          # Provide new component from extra blueprint.
#   s.property                              # Implicit `get_property(s, :property)`
#   s.property = value                      # Implicit `set_property!(s, :property, value)`
#
# Components and methods are organized into a dependency network,
# with components requiring each other
# and methods depending on the presence of certain components to run.
# This makes it possible to emit useful errors
# when lib users attempt to invoke the above behaviour
# but not all required components have been added to the system.
#
# Before being expanded into the components they provide,
# every blueprint is carefully checked by lib devs
# so they can guarantee that the internal state cannot be corrupted during expansion,
# and by the exposed System/Blueprints/Components/Methods interface in general.
#
# As a current limitation, there is no way to "remove" a component from the system,
# so the system evolution is monotonic.
# However, if the underlying wrapped value can be safely copied,
# then it is always possible to "fork" the system:
#
#   s = System{CopyableWrappedValue}(a::A, b::B, c::C)
#   fork = copy(s)
#   add!(fork, d::D)
#   has_component(fork, D) # True.
#   has_component(s, D) # False.
#
# This *may* make it useless to ever feature component removal.
module Framework

using Crayons
using MacroTools
using OrderedCollections

# Convenience aliases.
argerr(m) = throw(ArgumentError(m))
const Option{T} = Union{T,Nothing}
struct PhantomData{T} end
const I = Iterators

# ==========================================================================================
# Early small types declarations to avoid circular dependencies among code files.

# Abstract over various exception thrown during inconsistent use of the system.
abstract type SystemException <: Exception end

# The parametric type 'V' for components and blueprints
# is the type of the value wrapped by the system.
abstract type Component{V} end
abstract type Blueprint{V} end
export Component
export Blueprint

# Most framework internals work with component types because they can be abstract,
# most exposed methods work with concrete singleton instance.
const CompType{V} = Type{<:Component{V}}
# Abstract over either for exposed inputs.
const CompRef{V} = Union{Component{V},CompType{V}}

# Exception to be thrown by framework user from various extension points.
# This should not bubble up to toplevel scope, but be caught
# and upgraded differently depending on the context.
struct CheckError <: Exception
    message::String
end
checkfails(m::String; throw = Base.throw) = throw(CheckError(m))
checkfails(to_string::Function, e::Exception; throw = Base.throw) =
    checkfails(to_string(sprint(showerror, e)); throw)
checkfails(e::Exception; throw = Base.throw) = checkfails(identity, e; throw)
checkrefails(args...) = checkfails(args...; throw = Base.rethrow)
export checkfails, checkrefails

# ==========================================================================================
# Display.

const component_color = crayon"yellow"
const blueprint_color = crayon"blue"
const field_color = crayon"cyan"
const grayed = crayon"dark_gray"
const reset = crayon"reset"
cc(C) = "$component_color$C$reset"
bc(B) = "$blueprint_color$B$reset"
fc(C) = "$field_color$C$reset"

# Strip paths to identifiers up to some user-defined root(s).
const mod_roots = [] # <- Framework-level config.
function stripped_path(C::Type)
    name = C.name
    mod = name.module
    path = [strip_compname(nameof(C))]
    while !(mod in mod_roots)
        push!(path, nameof(mod))
        parent = parentmodule(mod)
        parent === mod && break # Reached toplevel.
        mod = parent
    end
    join(reverse(path), '.')
end

# ==========================================================================================

# Base structure.
include("./system.jl") #  <- Defines the 'System' type used in the next files..
include("./component.jl") # <- But better start reading from this file.
include("./blueprints.jl")
include("./methods.jl")
include("./properties.jl")
include("./plus_operator.jl")
include("./add.jl")

# Exposed macros.
include("./macro_helpers.jl")
include("./component_macro.jl")
include("./blueprint_macro.jl")
include("./conflicts_macro.jl")
include("./method_macro.jl")

end

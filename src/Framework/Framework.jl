# This framework is dedicated to wrap a sophisticated value into a 'System'.
#
# Motivation:
#
#   The wrapped value is powerful but complicated
#   and its state needs to be carefully maintained.
#   Lib devs want to expose it to their users so they can enjoy the benefit of it,
#   but they also want to protect them from the dangers of breaking the internal state.
#
# Instead of exposing the value directly,
# lib devs wrap it into a 'System':
#
#   s = System{WrappedValue}()
#
# And then they carefully develop an associated collection of 'components' and 'methods'.
#
# The whole module can be viewed as an extension of the "builder pattern".
# Instead of constructing the value directly,
# lib users will start from an "empty" base system,
# and populate it with the components at hand
# until it has all the component required to exhibit the behaviour they need
# via the 'methods' at hand.
#
# Consistently with this "builder" approach,
# 'components' are not actual values,
# but rather abstract, diffuse sets of data appended to the protected state.
# In consequence, lib users cannot get a 'component' variable
# referring to data inside the system.
# Instead, they get 'blueprints' for components,
# which they can construct and tweak as just regular julia structs.
# When ready, a blueprint can be read by the system, checked,
# and expanded into the actual components.
#
# No component can be added twice,
# and no blueprint can be read and expanded into different components types.
# As a consequence, 'Components' are implemented as julia DataTypes,
# and 'blueprint' are plain instances of these types:
#
#   component = Blueprint # Refers to the 'component' concept but not to data in the system.
#   blueprint = Blueprint(...) # Contains data later used to expand into a system component.
#
# TODO: the above design puts too much constraint on the blueprint/component relations.
#       refactor the framework to dissociate them into distinct sets of types.
#       Considering that blueprints imply/bring other blueprints,
#       it is even *wrong* now under certain aspects.
#       The fix is to separate component types from blueprint types,
#       but this requires deep refactoring with strong ergonomics consequences.
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
#   s = System{WrappedValue}(blueprints...) # Start with a sequence of initial components.
#   s += blueprint                          # Add component from extra blueprint.
#   s.property                              # Implicit `get_property_method(s)`
#   s.property = value                      # Implicit `set_property_method(s, value)`
#
# Components and methods are organized into a dependency hierarchy,
# with components requiring each other
# and methods depending on the presence of certain components to run.
# This makes it possible to emit useful errors
# when lib users attempt to invoke the above behaviour
# but not all required component have been added to the system.
#
# Before being expanded into a component,
# every blueprint is carefully checked by lib devs
# so they can guarantee that the internal state cannot be corrupted during expansion,
# and by the exposed System/Blueprint/Component/Method interface in general.
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

# TODO: Improve ergonomics:
#   - [x] Flesh early documentation.
#   - [x] Encourage moving sophisticated function definitions outside macro calls
#     to ease burden on `Revise`.
#   - [x] blueprints *optionnaly* bring other blueprints.
#   - [ ] "*blueprints* imply/bring *blueprints*", not "components imply/bring components"
#   - [ ] `depends(other_method_name)` to inherit all dependent components.
#   - [ ] Recurring pattern: various blueprints types provide 'the same component': reify.
#   - [ ] Namespace properties into like system.namespace.namespace.property.
#   - [ ] Hooks need to trigger when special components combination become available.
#         See for instance the expansion of `Nutrients.Nodes`.

using Crayons
using MacroTools
using OrderedCollections


# Base structure.
include("./component.jl")
include("./methods.jl")
include("./system.jl")
include("./add.jl")
include("./plus_operator.jl")

include("./exceptions.jl")

# Exposed macros.
include("./macro_helpers.jl")
include("./component_macro.jl")
include("./conflicts_macro.jl")
include("./method_macro.jl")

end

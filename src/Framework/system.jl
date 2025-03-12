# Components consist in data stored to a value wrapped in a 'System'.
# The system keeps track of all the components added.
# It also checks that the method called and properties invoked
# do meet the components requirements.
#
# The whole framework responsibility is to ensure consistency of the wrapped value.
# As a consequence, don't leak references to it or its inner data
# unless user cannot corrupt the value state through them.
#
# The value wrapped needs to be constructible from no arguments,
# so the user can start with an "empty system".
#
# The value wrapped needs to be copy-able for the system to be forked.

struct RawConstruct end # Used to dispatch constructor.

# The 'system' newtypes any possible value::V.
# V needs to be copy-able for the system to be forked.
struct System{V}

    _value::V

    # Keep track of all the concrete components added.
    _concrete::OrderedSet{CompType{V}} # (ordered to be used as a history)

    # Components are also indexed by their possible abstract supertypes.
    _abstract::Dict{CompType{V},Set{CompType{V}}} # {Abstract -> {Concrete}}

    # Construct the initial value in-place
    # so that its state cannot be corrupted if outer aliased refs
    # are still lingering on within the caller scope.
    System{V}(args...; kwargs...) where {V} =
        new{V}(V(args...; kwargs...), OrderedSet(), Dict())

    # Or with a starting list of components,
    # assuming the value can be constructed with no arguments.
    function System{V}(blueprints::Blueprint{V}...) where {V}
        system = System{V}()
        for bp in blueprints
            add!(system, bp)
        end
        system
    end

    # Specialize the empty case to avoid infinite recursion.
    System{V}() where {V} = new{V}(V(), OrderedSet(), Dict())

    # Useful when copying.
    System{V}(::Type{RawConstruct}, args...) where {V} = new{V}(args...)

end
export System

system_value_type(::Type{System{V}}) where {V} = V
system_value_type(::System{V}) where {V} = V
value(s::System) = getfield(s, :_value) # Bypass properties checks.

#-------------------------------------------------------------------------------------------
# Fork the system, recursively copying the wrapped value and every component.
function Base.copy(s::System{V}) where {V}
    value = copy(s._value)
    concrete = copy(s._concrete)
    abstracts = Dict(A => Set(concretes) for (A, concretes) in s._abstract)
    System{V}(RawConstruct, value, concrete, abstracts)
end

#-------------------------------------------------------------------------------------------
# Query components.

# Iterate over all concrete components.
component_types(s::System) = imap(identity, s._concrete)
components(s::System) = imap(singleton_instance, component_types(s))
# Restrict to the given component (super)type.
components_types(system::System{V}, C::CompType{V}) where {V} =
    if isabstracttype(C)
        d = system._abstract
        haskey(d, C) ? d[C] : ()
    else
        d = system._concrete
        C in d ? (C,) : ()
    end
components(s::System, C::CompType{V}) where {V} =
    imap(singleton_instance, components_types(s, C))
export components, component_types

# Basic check.
has_component(s::System{V}, C::Type{<:Component{V}}) where {V} = !isempty(components(s, C))
has_component(s::System{V}, c::Component{V}) where {V} = has_component(s, typeof(c))
has_concrete_component(s::System{V}, c::Component{V}) where {V} = typeof(c) in s._concrete
export has_component, has_concrete_component

#-------------------------------------------------------------------------------------------

# Basic recursive equivalence relation.
function equal_fields(a::T, b::T) where {T}
    for name in fieldnames(T)
        u, v = getfield.((a, b), name)
        u == v || return false
    end
    true
end
Base.:(==)(a::System{U}, b::System{V}) where {U,V} = U == V && equal_fields(a, b)
Base.:(==)(a::Blueprint{U}, b::Blueprint{V}) where {U,V} =
    U == V && typeof(a) == typeof(b) && equal_fields(a, b)

# ==========================================================================================
# Dedicated exceptions.

struct SystemError{V} <: SystemException
    message::String
    _::PhantomData{V}
    SystemError(::Type{V}, m) where {V} = new{V}(m, PhantomData{V}())
end

function Base.showerror(io::IO, e::SystemError{V}) where {V}
    println(io, "In system for '$V': $(e.message)")
end

syserr(V, m) = throw(SystemError(V, m))

# ==========================================================================================
# Display.
function Base.show(io::IO, sys::System)
    n = length(sys._concrete)
    print(io, "$(typeof(sys)) with $n component$(s(n)).")
end

function Base.show(io::IO, ::MIME"text/plain", sys::System)
    n = length(sys._concrete)
    S = typeof(sys)
    rs = repr(MIME("text/plain"), S)
    print(io, "$rs with $n component$(eol(n))")
    for C in sys._concrete
        print(io, "\n  - ")
        shortline(io, sys, singleton_instance(C))
    end
end
s(n) = (n > 1) ? "s" : ""
eol(n) = s(n) * (n == 0 ? "." : ":")

# For specialization by framework users.
shortline(io::IO, ::System, C::CompType) = @invoke show(io, C::CompType)
shortline(io::IO, s::System, c::Component) = shortline(io, s, component_type(c))

# Components append data to a value wrapped in a 'System'.
# The system keeps track of all the blueprints used to add components their dependencies.
# It also checks that the method called and properties invoked
# do meet the components requirements.
#
# The whole framework responsibility is to ensure consistency of the wrapped value.
# As a consequence, don't leak references to it or its inner data
# unless user cannot corrupt the value state through them.
#
# The value wrapped needs to be copy-able for the system to be forked.
# So do the components blueprints.

struct RawConstruct end # Used to dispatch constructor.

# The 'system' newtypes any possible value::V.
# V needs to be copy-able for the system to be forked.
struct System{V}

    _value::V

    # Keep track of the blueprints used (some may have been 'implied' or 'brought'),
    # effectively indexing all added components by their *concrete* types.
    _blueprints::OrderedDict{Component{V},Blueprint{V}} # (ordered to be used as a history)

    # Components added are also indexed by their possible abstract supertypes.
    _abstracts::Dict{Component{V},Set{Component{V}}} # {Abstract -> {Concrete}}

    # Construct the initial value in-place
    # so that its state cannot be corrupted if outer aliased refs
    # are still lingering on within the caller scope.
    System{V}(args...; kwargs...) where {V} =
        new{V}(V(args...; kwargs...), OrderedDict(), Dict())

    # Construct value with no arguments.
    System{V}() where {V} = new{V}(V(), OrderedDict(), Dict())

    # Or with a starting list of components.
    function System{V}(blueprints::Blueprint{V}...) where {V}
        system = System{V}()
        for bp in blueprints
            add!(system, bp)
        end
        system
    end

    # Useful when copying.
    System{V}(::Type{RawConstruct}, args...) where {V} = new{V}(args...)

end
export System

valuetype(::System{V}) where {V} = V

#-------------------------------------------------------------------------------------------
# Fork the system, recursively copying the wrapped value and every component.
function Base.copy(s::System{V}) where {V}
    value = copy(s._value)
    blueprints = OrderedDict(C => copy(b) for (C, b) in s._blueprints)
    abstracts = Dict(A => Set(concretes) for (A, concretes) in s._abstracts)
    System{V}(RawConstruct, value, blueprints, abstracts)
end

#-------------------------------------------------------------------------------------------
# The system fields are considered private, and the wrapped value in particular,
# but they can be accessed via a set of properties enabled by the components/methods.

function Base.getproperty(system::System{V}, p::Symbol) where {V}
    nameerr() = syserr(V, "Invalid property name: '$p'.")
    # Authorize direct accesses to private fields.
    p in fieldnames(System) && return getfield(system, p)
    # Search property method.
    haskey(PROPERTIES, V) || nameerr()
    props = PROPERTIES[V]
    haskey(props, p) || nameerr()
    fn = props[p].read
    # Check for required components availability.
    miss = missing_dependency_for(V, fn, system)
    if !isnothing(miss)
        comp = isabstracttype(miss) ? "A component '$miss'" : "Component '$miss'"
        properr(V, p, "$comp is required to read this property.")
    end
    # Forward to method.
    fn(system)
end

function Base.setproperty!(system::System{V}, p::Symbol, rhs) where {V}
    nameerr() = syserr(V, "Invalid property name: '$p'.")
    # Authorize direct accesses to private fields.
    p in fieldnames(System) && return setfield(system, p, rhs)
    # Search property method.
    haskey(PROPERTIES, V) || nameerr()
    props = PROPERTIES[V]
    haskey(props, p) || nameerr()
    fn = props[p].write
    isnothing(fn) && properr(V, p, "This property is read-only.")
    # Check for required components availability.
    miss = missing_dependency_for(V, fn, system)
    if !isnothing(miss)
        comp = isabstracttype(miss) ? "A component '$miss'" : "Component '$miss'"
        properr(V, p, "$comp is required to write to this property.")
    end
    # Invoke property method, checking for available components.
    fn(system, rhs)
end

# In case the client agrees,
# also forward the properties to the wrapped value.
# Note that this happens without checking dependent components.
# Still, a lot of things *are* checked, so this 'unchecked' does *not* mean 'performant'.
function unchecked_getproperty(value::V, p::Symbol) where {V}
    perr(mess) = properr(V, p, mess)
    p in fieldnames(V) && return getfield(value, p)
    haskey(PROPERTIES, V) || perr("Neither a field of '$V' nor a property.")
    props = PROPERTIES[V]
    haskey(props, p) || perr("Neither a field of '$V' nor a property.")
    props[p].read(value)
end

function unchecked_setproperty!(value::V, p::Symbol, rhs) where {V}
    perr(mess) = properr(V, p, mess)
    p in fieldnames(V) && return setfield!(value, p, rhs)
    haskey(PROPERTIES, V) || perr("Neither a field or a property.")
    props = PROPERTIES[V]
    haskey(props, p) || perr("Neither a field or a property.")
    fn = props[p].write
    isnothing(fn) && properr(V, p, "Property is not writable.")
    fn(value, rhs)
end

#-------------------------------------------------------------------------------------------
# Query components.

# Iterate over all blueprints with the given component type.
inner_blueprints(system::System, c::Component) =
    if isabstracttype(c)
        d = system._abstracts
        haskey(d, c) ? Iterators.map(T -> system._blueprints[T], d[c]) : ()
    else
        d = system._blueprints
        haskey(d, c) ? (d[c],) : ()
    end

# Iterate over all concrete components.
components(s::System) = keys(s._blueprints)
# Restrict to the given component (super)type.
components(s::System, c::Component) = (typeof(bp) for bp in inner_blueprints(s, c))
export components

# Basic check.
has_component(s::System, c::Component) = !isempty(inner_blueprints(s, c))
export has_component

# List all blueprint used to expand this instance.
# (don't leak aliased refs)
blueprints(s::System) = Set(copy(bp) for bp in values(s._blueprints))
export blueprints

# List properties available for this instance.
# Returns {:propname => is_writeable}
function properties(s::System{V}) where {V}
    res = Dict{Symbol,Bool}()
    haskey(PROPERTIES, V) || return res
    for (name, prop) in PROPERTIES[V]
        readable = isnothing(missing_dependency_for(V, prop.read, s))
        if isnothing(prop.write)
            writeable = false
        else
            writeable = isnothing(missing_dependency_for(V, prop.write, s))
        end
        readable && (res[name] = writeable)
    end
    res
end
export properties

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

#-------------------------------------------------------------------------------------------
# Display.
function Base.show(io::IO, sys::System)
    n = length(sys._blueprints)
    print(io, "$(typeof(sys)) with $n component$(s(n)).")
end

function Base.show(io::IO, ::MIME"text/plain", sys::System)
    n = length(sys._blueprints)
    S = typeof(sys)
    rs = repr(MIME("text/plain"), S)
    print(io, "$rs with $n component$(eol(n))")
    for component in keys(sys._blueprints)
        print(io, "\n  - $(display(sys._value, component))")
    end
end
s(n) = (n > 1) ? "s" : ""
eol(n) = s(n) * (n == 0 ? "." : ":")

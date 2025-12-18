# Methods with these exact signatures:
#
#   - method(v::Value)
#   - method!(v::Value, rhs)
#
# .. can optionally become properties of the system/value,
# in the sense of julia's `getproperty/setproperty!`.
#
# The properties come in two styles:
#
#   - system.property -> Checks that the required components exist.
#   - value.property -> Runs and see what happens.
#
# Properties can be namespaced into packed accessors like:
#
#   system.space.a
#   system.space.b
#   system.other.subspace.a # (different from 'space.a')
#
# Where `system.space` and `system.other.subspace` are raw opaque accessor types
# called *property spaces*
# wrapping a simple reference to the underlying systems.

# In this context, 'P' or *property target*
# refers to either the wrapped system value type
# *or* a property space dedicated to systems for this value type.

# ==========================================================================================
# Properties space forward `.name` accesses.

struct PropertySpace{name,P,V}
    _system::System{V}
end

const PropertyTargetType = Union{Type{<:System},Type{<:PropertySpace}}
const PropertyTarget = Union{System,PropertySpace}

# Basic queries.
system_value_type(::Type{PropertySpace{name,P,V}}) where {name,P,V} = V
property_name(::Type{PropertySpace{name,P,V}}) where {name,P,V} = name
super(::Type{PropertySpace{name,P,V}}) where {name,P,V} = P
system_value_type(sp::PropertySpace) = system_value_type(typeof(sp))
property_name(sp::PropertySpace) = property_name(typeof(sp))
super(sp::PropertySpace) = super(typeof(sp))
system(p::PropertySpace) = getfield(p, :_system) # Bypass property checks.
value(p::PropertySpace) = value(system(p))
system(s::System) = s # Consistency accross targets.

# Climb up the types hierarchy to reconstruct `.path.to.concrete.property`.
# (the result is a reversed tuple)
names_sequence(::Type{PropertySpace{name,P,V}}) where {name,P,V} =
    (name, names_sequence(P)...)
names_sequence(::Type{System{V}}) where {V} = () # Root.
# Convert to a :(a.b.c) expression.
function path(P::PropertyTargetType)
    res = nothing
    for name in reverse(names_sequence(P))
        if isnothing(res)
            res = name
        else
            res = :($res.$name)
        end
    end
    res
end
path(x) = path(typeof(x))
names_sequence(p::PropertyTarget) = names_sequence(typeof(p))

# ==========================================================================================
# Basic property accesses.

# Factorize for reuse with properties spaces.
function Base.getproperty(target::P, pname::Symbol) where {P<:PropertyTarget}
    # Search property method.
    fn = read_property(P, Val(pname))
    # Check for required components availability.
    miss = first_missing_dependency_for(fn, target)
    if !isnothing(miss)
        comp = isabstracttype(miss) ? "A component $miss" : "Component $miss"
        properr(P, pname, "$comp is required to read this property.")
    end
    # Forward to method.
    fn(target)
end

function Base.setproperty!(target::P, pname::Symbol, rhs) where {P<:PropertyTarget}
    # Search property method.
    fn = readwrite_property(P, Val(pname))
    # Check for required components availability.
    miss = first_missing_dependency_for(fn, target)
    if !isnothing(miss)
        comp = isabstracttype(miss) ? "A component $miss" : "Component $miss"
        properr(P, pname, "$comp is required to write to this property.")
    end
    # Invoke property method.
    fn(target, rhs)
end

# In case the framework user agrees,
# also forward the properties to the wrapped value.
# Note that this happens without checking dependent components,
# and that the `; _system` hook cannot be provided then in this context.
# Still, a lot of things *are* checked, so this 'unchecked' does *not* mean 'performant'.
function unchecked_getproperty(value::V, p::Symbol) where {V}
    p in fieldnames(V) && return getfield(value, p)
    fn = read_property(System{V}, Val(p))
    fn(value)
end

function unchecked_setproperty!(value::V, p::Symbol, rhs) where {V}
    perr(mess) = properr(System{V}, p, mess)
    p in fieldnames(V) && return setfield!(value, p, rhs)
    fn = readwrite_property(System{V}, Val(p))
    fn(value, rhs)
end

# ==========================================================================================
# Define properties within the framework.

# Map wrapped system value and property name to the corresponding function.
read_property(P::PropertyTargetType, ::Val{name}) where {name} =
    throw(PropertyError(P, name, "Unknown property."))
write_property(P::PropertyTargetType, ::Val{name}) where {name} =
    throw(PropertyError(P, name, "Unknown property."))

has_read_property(P::PropertyTargetType, n::Val{name}) where {name} =
    try
        read_property(P, n)
        true
    catch e
        e isa PropertyError || rethrow(e)
        false
    end

possible_write_property(P::PropertyTargetType, n::Val{name}) where {name} =
    try
        write_property(P, n)
    catch e
        e isa PropertyError || rethrow(e)
        nothing
    end

has_write_property(P::PropertyTargetType, n::Val{name}) where {name} =
    !isnothing(possible_write_property(P, n))

function readwrite_property(P::PropertyTargetType, n::Val{name}) where {name}
    read_property(P, n) # Errors if not even 'read-'.
    try
        write_property(P, n)
    catch e
        e isa PropertyError || rethrow(e)
        rethrow(PropertyError(P, name, "This property is read-only."))
    end
end

# Set read property first..
function set_read_property!(P::PropertyTargetType, name::Symbol, fn::Function)
    REVISING ||
        has_read_property(P, Val(name)) &&
            properr(P, name, "Readable property already exists.")
    # Dynamically add method to connect property name to the given function.
    name = Meta.quot(name)
    eval(quote
        read_property(::Type{$P}, ::Val{$name}) = $fn
    end)
end

# .. and only after, and optionally, the corresponding write property.
function set_write_property!(P::PropertyTargetType, name::Symbol, fn::Function)
    has_read_property(P, Val(name)) || properr(
        P,
        name,
        "Property cannot be set writable \
         without having been set readable first.",
    )
    REVISING ||
        has_write_property(P, Val(name)) &&
            properr(P, name, "Writable property already exists.")
    name = Meta.quot(name)
    eval(quote
        write_property(::Type{$P}, ::Val{$name}) = $fn
    end)
end

# ==========================================================================================
# List all properties and associated functions for this type.
# Yields (property_name, fn_read, Option{fn_write}, iterator{dependencies...}).

function properties(P::PropertyTargetType)
    I.map(
        I.filter(methods(read_property, Tuple{Type{P},Val}, Framework)) do mth
            mth.sig isa UnionAll && return false # Only consider concrete implementations.
            val = mth.sig.types[end]
            val <: Val ||
                throw("Unexpected method signature for $read_property: $(mth.sig)")
            val !== Val # Omit generic implementation.
        end,
    ) do mth
        val = mth.sig.types[end]
        name = first(val.parameters)
        read_fn = read_property(P, Val(name))
        write_fn = possible_write_property(P, Val(name))
        (name, read_fn, write_fn, I.map(identity, depends(P, read_fn)))
    end
end
export properties

# List properties available for *this* particular instance.
# Yields (:propname, read, Option{write})
function properties(target::PropertyTarget)
    I.map(
        I.filter(properties(typeof(target))) do (_, read, _, _)
            isnothing(first_missing_dependency_for(read, target))
        end,
    ) do (name, read, write, _)
        (name, read, write)
    end
end

# List *unavailable* properties for this instance
# along with the components missing to support them.
# Yields (:propname, read, Option{write}, iterator{missing_dependencies...})
function latent_properties(target::PropertyTarget)
    I.map(
        I.filter(properties(typeof(target))) do (_, read, _, _)
            !isnothing(first_missing_dependency_for(read, target))
        end,
    ) do (name, read, write, deps)
        (name, read, write, I.filter(d -> !has_component(target, d), deps))
    end
end
export latent_properties

# Consistency + REPL completion.
Base.propertynames(target::PropertyTarget) = I.map(first, properties(target))

# ==========================================================================================
# Helper macro to define deep nested type paths.

macro PropertySpace(path, V)
    try
        property_space_type(path, Core.eval(__module__, V))
    catch e
        src = __source__
        blue = crayon"blue"
        res = crayon"reset"
        @warn "Error in macro at $blue$(src.file):$(src.line)$res"
        rethrow(e)
    end
end
export @PropertySpace

function property_space_type(path, V)
    is_identifier_path(path) || argerr("Not an identifier path: $(repr(path)).")
    res = nothing
    for step in collect_path(path)
        if isnothing(res)
            res = PropertySpace{step,System{V},V}
        else
            res = PropertySpace{step,res,V}
        end
    end
    res
end

# ==========================================================================================
# Dedicated exceptions.

struct PropertyError{P} <: SystemException
    name::Symbol
    message::String
    _::PhantomData{P}
    PropertyError(::Type{P}, s, m) where {P} = new{P}(s, m, PhantomData{P}())
end
super(::PropertyError{P}) where {P} = P

function Base.showerror(io::IO, e::PropertyError{P}) where {P}
    (; name, message) = e
    V = system_value_type(P)
    pth = path(P)
    isnothing(pth) && (pth = "")
    println(io, "In property `$pth.$name` of '$V': $message")
end

properr(P, n, m) = throw(PropertyError(P, n, m))

# ==========================================================================================
# Display property types.

Base.show(io::IO, ::Type{PropertySpace}) = @invoke show(io::IO, PropertySpace::Type)
function Base.show(io::IO, P::Type{<:PropertySpace})
    V = system_value_type(P)
    @invoke show(io::IO, PropertySpace::Type)
    print(io, "{<")
    for name in reverse(names_sequence(P))
        print(io, ".$name")
    end
    print(io, ">, $V}")
end


# Extension point: provide custom property list to possibly filter among them.
Base.show(io::IO, p::PropertySpace) = display_long(io, p, properties)
function display_long(io::IO, p::PropertySpace, properties::Function)
    V = system_value_type(p)
    print(io, "Property space for '$(V)': ", crayon"black bold")
    for name in reverse(names_sequence(p))
        print(io, ".$name")
    end
    print(io, crayon"reset")
    for (name, _) in properties(p)
        print("\n  .$name")
    end
end

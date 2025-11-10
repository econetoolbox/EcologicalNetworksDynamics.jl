# The main value, wrapped into a System, is what we hand out to user as "the model".
# Use this file to define simplified framework primitives
# under the hypothesis that the only system value we will work with
# is the ecological model.
# The purpose is to make subsequent code in `./components`, `simulate.jl` etc.
# easier to read and write.

# Fine-grained namespace control.
import .Framework
const F = Framework # Convenience alias for the whole components library.
import .F:
    @blueprint,
    @component,
    @conflicts,
    @method,
    Brought,
    CheckError,
    System,
    add!,
    blueprints,
    checkfails,
    checkrefails,
    components,
    does_bring,
    does_embed,
    does_imply,
    embedded,
    has_component,
    implied,
    isacomponent

# Direct re-exports from the framework module.
export add!
export blueprints
export components
export does_bring
export does_embed
export does_imply
export embedded
export has_component
export implied
export isacomponent
export properties

# The type wrapped within the system.
const Internal = Networks.Network

const Blueprint = F.Blueprint{Internal}
const BlueprintSum = F.BlueprintSum{Internal}
const CompType = F.CompType{Internal}
const Component = F.Component{Internal}

const Model = F.System{Internal}
export Model

# Skip _-prefixed properties.
function properties(m::Model)
    res = []
    for (name, _) in F.properties(m)
        startswith(String(name), '_') && continue
        push!(res, name)
    end
    sort!(res)
    res
end
non_underscore(p::F.PropertySpace) =
    I.filter(F.properties(p)) do (name, _)
        !startswith(String(name), '_')
    end
properties(p::F.PropertySpace) = collect(I.map(first, non_underscore(p)))
export properties
Base.propertynames(m::Model) = properties(m)
Base.propertynames(p::F.PropertySpace{name,P,Internal}) where {name,P} = properties(p)

# Convenience macro to define property space.
macro propspace(path)
    get = Symbol(:get_, path)
    eget = esc(get)
    quote
        $eget(::Internal, s::Model) = F.@PropertySpace($path, $Internal)(s)
        F.@method $get{$Internal} read_as($path)
    end
end

# ==========================================================================================
# The above defines var"get_a.b" method names for nested properties
# to avoid possible ambiguity with `get_a_b`.
# Use this pattern for all propspace uses
# and these convenience macro to call these methods on raw values.

macro ref(raw, path)
    read(:ref, raw, path)
end

macro get(raw, path)
    read(:get, raw, path)
end

macro set!(raw, path, rhs)
    write(raw, path, rhs)
end

# Convenience idiomatic syntax:
# @ref var.path.to.prop
# @get var.path.to.prop
macro ref(path)
    convenience_read(__source__, :ref, path)
end
macro get(path)
    convenience_read(__source__, :get, path)
end
function convenience_read(src, kw, path)
    err(m) = throw(AccessError(kw, m, src))
    F.is_identifier_path(path) || err("Not an access path: $(repr(path)).")
    var, path... = F.collect_path(path)
    read(kw, var, join_path(path))
end

# @set var.path.to.prop = rhs
macro set(input)
    err(m) = throw(AccessError(:set, m, __source__))
    (false) && (local path, rhs)
    @capture(input, path_ = rhs_)
    isnothing(path) && err("Not a `path = rhs` expression: $(repr(input))")
    F.is_identifier_path(path) || err("Not an access path: $(repr(path)).")
    var, path... = F.collect_path(path)
    write(var, join_path(path), rhs)
end

# Actual code generation.
function read(kw, raw, path)
    target, name = to_target_name(path, kw == :ref)
    raw = esc(raw)
    quote
        F.read_property($target, Val($name))($raw)
    end
end

function write(raw, path, rhs)
    target, name = to_target_name(path, false)
    raw, rhs = esc.((raw, rhs))
    quote
        F.readwrite_property($target, Val($name))($raw, $rhs)
    end
end

function to_target_name(path, is_ref)
    target, name = split_last(path)
    target = isnothing(target) ? Model : F.property_space_type(target, Internal)
    if is_ref  # Standard in the next: `_`-prefixed are ref propnames.
        name = Symbol(:_, name)
    end
    name = Meta.quot(name)
    (target, name)
end

# Assuming path is checked: :(a.b.c) -> (:(a.b), :c)
function split_last(path)
    path isa Symbol && return (nothing, path)
    @capture(path, a_.b_)
    (a, b)
end

function join_path(v)
    prop = last(v)
    if length(v) == 1
        prop
    else
        head = join_path(v[1:end-1])
        :($head.$prop)
    end
end

# Dedicated errors.
struct AccessError
    type::Symbol
    message::String
    src::LineNumberNode
end
function Base.showerror(io::IO, e::AccessError)
    print(io, "In @$(e.type) access: ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

# ==========================================================================================
# Display.

push!(F.mod_roots, EcologicalNetworksDynamics)

Base.show(io::IO, ::Type{Model}) = print(io, "Model")

Base.show(io::IO, ::MIME"text/plain", I::Type{Internal}) = Base.show(io, I)
Base.show(io::IO, ::MIME"text/plain", ::Type{Model}) =
    print(io, "Model $(crayon"dark_gray")(alias for $System{$Internal})$(crayon"reset")")

# Filter out _-prefixed names.
Base.show(io::IO, p::F.PropertySpace{name,P,Internal}) where {name,P} =
    F.display_long(io, p, non_underscore)

#-------------------------------------------------------------------------------------------
# Default display for blueprint fields.

# Vector.
function F.display_blueprint_field_short(io::IO, v::AbstractVector, ::Blueprint)
    print(io, "[$(join_elided(v, ", "))]")
end

# Matrix.
function F.display_blueprint_field_short(io::IO, m::AbstractMatrix, ::Blueprint)
    (p, q) = size(m)
    print(io, "$p×$q matrix (")
    min, max = extrema(m)
    if min == max
        print(io, "$min")
    else
        print(io, "$min to $max")
    end
    print(io, ")")
end

# Sparse matrix.
function F.display_blueprint_field_short(io::IO, m::SparseMatrix, ::Blueprint)
    (p, q) = size(m)
    print(io, "$p×$q ")
    _, _, values = findnz(m)
    n = length(values)
    if n == 0
        print(io, "empty sparse matrix")
    else
        print(io, "sparse matrix with $n values (")
        min, max = extrema(values)
        if min == max
            print(io, "$min")
        else
            print(io, "$min to $max")
        end
        print(io, ")")
    end
end

# Map.
function F.display_blueprint_field_short(
    io::IO,
    map::@GraphData(Map{T}),
    ::Blueprint,
) where {T}
    it = I.map(map) do (k, v)
        "$k: $v"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Adjacency list.
function F.display_blueprint_field_short(
    io::IO,
    adj::@GraphData(Adjacency{T}),
    bp::Blueprint,
) where {T}
    it = I.map(adj) do (k, v)
        "$k: $(sprint(F.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Binary map.
function F.display_blueprint_field_short(io::IO, set::@GraphData(Map{:bin}), ::Blueprint)
    print(io, "{$(join_elided(set, ", "; repr = false))}")
end

# Binary adjacency list.
function F.display_blueprint_field_short(
    io::IO,
    adj::@GraphData(Adjacency{:bin}),
    bp::Blueprint,
)
    it = I.map(adj) do (k, v)
        "$k: $(sprint(F.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Defer long to short by default.
F.display_blueprint_field_long(io::IO, v, bp::Blueprint) =
    F.display_blueprint_field_short(io, v, bp)

# ==========================================================================================

@doc """
Model is the main object that we hand out to user
which contains all the information about the underlying ecological model.

# Create a Model

The most straightforward way to create a model is to use [`default_model`](@ref).
This function only requires you to specify the trophic network.

```julia
fw = [1 => 2, 2 => 3]
model = default_model(fw)
```

This function will help you to create a model with ease,
however it relies on default values for the parameters,
which are not always suitable for your specific case,
even though extracted from the literature.

To create a model with custom parameters, you can pass
other arguments to `default_model`.

```julia
model = default_model(fw, BodyMass(; Z = 100))
```

For instance, the above example creates a model with a
body mass distribution with a predator-prey mass ratio of 100.

It is also possible to create a model manually by adding the components one by one.
First, create an empty model:

```julia
m = Model()
```

Then add your components one by one.
Note that you have to add the components in the right order, as some components depend on others.
Moreover, some components are mandatory.
Specifically, you need to provide a food web, species body masses, a functional response, metabolic rates and a producer growth function.

```julia
m = Model()
m += Foodweb([3 => 2, 2 => 1])
m += ClassicResponse(; h = 2, M = BodyMass([0.1, 2, 3]))
m += LogisticGrowth(; r = 1, K = 10)
m += Metabolism(:Miele2019)
m += Mortality(0)
```

# Read and write properties of the model

First all properties contained in the model
can be listed with:

```julia
properties(m) # Where m is a Model.
```

Then, the value of a property can be read with
`get_<X>` where `X` is the name of the property.
For instance, to read mortality rates:

```julia
get_mortality(m) # Equivalent to: m.mortality.
```

You can also re-write properties of the model using `set_<X>!`.
However, not all properties can be re-written,
because some of them are derived from the others.
For instance, many parameters are derived from species body masses,
therefore changing body masses would make the model inconsistent.
However, terminal properties can be re-written, as the species metabolic rate.
""" Model

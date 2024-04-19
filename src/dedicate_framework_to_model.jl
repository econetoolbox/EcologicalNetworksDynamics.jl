# The main value, wrapped into a System, is what we hand out to user as "the model".

const InnerParms = Internals.ModelParameters # <- TODO: rename when refactoring Internals.

"""
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
"""
const Model = System{InnerParms}

const ModelBlueprint = Blueprint{InnerParms}
const ModelBlueprintSum = Framework.BlueprintSum{InnerParms}
const ModelComponent = Component{InnerParms}
export Model
export has_component

# Short alias to make it easier to add methods as F.expand!(..)
# rather than Framework.expand!(..).
const F = Framework

# Willing to make use of "properties" even for the wrapped value.
Base.getproperty(v::InnerParms, p::Symbol) = Framework.unchecked_getproperty(v, p)
Base.setproperty!(v::InnerParms, p::Symbol, rhs) =
    Framework.unchecked_setproperty!(v, p, rhs)

# Skip _-prefixed properties.
function properties(s::Model)
    res = []
    for (name, _) in F.properties(s)
        startswith(String(name), '_') && continue
        push!(res, name)
    end
    sort!(res)
    res
end

# ==========================================================================================
# Display.
Base.show(io::IO, ::Type{InnerParms}) = print(io, "<inner parms>") # Shorten and opacify.
Base.show(io::IO, ::Type{Model}) = print(io, "Model")

Base.show(io::IO, ::MIME"text/plain", I::Type{InnerParms}) = Base.show(io, I)
Base.show(io::IO, ::MIME"text/plain", ::Type{Model}) =
    print(io, "Model $(crayon"dark_gray")(alias for $System{$InnerParms})$(crayon"reset")")

# Useful to override in the case "different blueprints provide the same component"?
function display_short(b::ModelBlueprint, C::Component = typeof(b))
    res = "blueprint for $C("
    res *= join(Iterators.map(fieldnames(typeof(b))) do name
        value = getfield(b, name)
        # Special-case types that would clutter output.
        res = "$name: "
        res *= if value isa AliasingDicts.AliasingDict
            AliasingDicts.display_short(value)
        elseif value isa Union{Map,Adjacency,BinMap,BinAdjacency}
            t = if value isa Union{Map,BinMap}
                "map"
            else
                "adjacency"
            end
            t * GraphDataInputs.display_short(value)
        else
            repr(value)
        end
    end, ", ")
    res * ")"
end

function display_long(b::ModelBlueprint, c::Component = typeof(b); level = 0)
    res = "blueprint for $c:"
    level += 1
    for name in fieldnames(typeof(b))
        value = getfield(b, name)
        res *= "\n" * repeat("  ", level) * "$name: "
        # Special-case types that need proper indenting
        if value isa AliasingDicts.AliasingDict
            res *= AliasingDicts.display_long(value; level)
        elseif value isa GraphDataInputs.UList
            t = if value isa GraphDataInputs.UMap
                "map"
            else
                "adjacency"
            end
            res *= t * GraphDataInputs.display_long(value; level)
        elseif value isa ModelBlueprint
            res *= display_long(value; level)
        else
            res *= repr(
                MIME("text/plain"),
                value;
                context = IOContext(IOBuffer(), :color => true),
            )
        end
    end
    res
end

Base.show(io::IO, b::ModelBlueprint) = print(io, display_short(b))
Base.show(io::IO, ::MIME"text/plain", b::ModelBlueprint) = print(io, display_long(b))

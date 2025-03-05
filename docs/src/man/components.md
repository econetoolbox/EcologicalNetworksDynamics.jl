# The Ecological Model and Components

The package `EcologicalNetworksDynamics`
represents an ecological network as a julia value of type [`Model`](@ref).

```@setup econetd
using EcologicalNetworksDynamics
using Crayons
function showerr(e)
  print(stderr, "$(crayon"red")ERROR:$(crayon"reset") ")
  showerror(stderr, e)
  nothing
end
```

```@example econetd
m = default_model(Foodweb([:a => :b, :b => :c]))
```
Values of this type essentially describe a *graph*,
with various *nodes* compartments representing
*e.g.* species or nutrients
and various *edges* compartments representing
*e.g.* trophic links, or facilitation links.
In addition to the network topology,
the model also holds *data* describing the model further,
and brought by the various models *components*.
There are three possible "levels" for this data:
- __Graph-level__ data describe properties of the whole system.
  *e.g.*  temperature, hill-exponent *etc.*
  These are typically *scalar* values.
- __Node-level__ data describe properties
  of particular nodes in the graph:
  *e.g.* species body mass, nutrients turnover *etc.*
  These are typically *vector* values.
- __Edge-level__ data describe properties of particular links:
  *e.g.* trophic links efficiency,
  half-saturation of a producer-to-nutrient links *etc.*
  These are typically *matrix* values.

## Model Properties

The data held by the model can be accessed via the various model *properties*,
accessed with julia's `m.<P>` property accessor:
```@example econetd
m.hill_exponent # Graph-level data (a number).
m.body_mass     # Node-level data (a vector with one value per species).
m.efficiency    # Edge-level data (a matrix with one value per species interaction).
nothing # hide
```

Properties are grouped into *property spaces*:
```@example econetd
m.species
```

You can navigate the property spaces with successive `.` accesses:
```@example econetd
m.species.number
```

```@example econetd
m.trophic.matrix
```

Some data can be modified this way with `m.<P> = <value>`.
But *not all*:
```@example econetd
# Okay: this is terminal data.
m.hill_exponent = 2.1

try # hide
# Not okay: this could make the rest of the model data inconsistent.
m.species.richness = 4
catch e showerr(e) end # hide
```

If you need a model with different values for read-only data,
you need to build a new model with the values you desire.
```@example econetd
m = default_model(Foodweb([:a => :b, :b => [:c, :d]])) # Re-construct with a 4th species.
m.species.richness # Now the value is what you want.
```

The full list of available model properties can be queried with:
```@example econetd
properties(m)
nothing # hide
```

Some properties are just convenience aliases for each other.
```@example econetd
m.A == m.trophic.matrix
nothing # hide
```

## Model Components

The [`Model`](@ref) value is very flexible
and can represent a variety of different networks.
It is made from the combination of various *components*.

### Empty Model and the `add!` Method

When you start from a [`default_model`](@ref),
you typically obtain a full-fledged value,
with all the components required to simulate the dynamics.
Alternately, you can start from an empty model:

```@example econetd
m = Model()
```

In this situation, you need to add the components one by one.
But this gives you full control over the model content.

An empty model cannot be simulated,
because the data required for simulation is missing from it.
```@example econetd
try # hide
simulate(m, 0.5, 100)
catch e showerr(e) end # hide
```

Also, an empty model cannot be queried for data,
because there is no data inside:
```@example econetd
try # hide
m.richness
catch e showerr(e) end # hide
```

The most basic way to add a [`Species`](@ref) component to your model
is to use the [`add!`](@ref) function:
```@example econetd
add!(m, Species(3))
```

Now that the [`Species`](@ref) component has been added,
the related properties can be queried from the model:
```@example econetd
m.species.richness
```
```@example econetd
m.species.names
```

But the other properties cannot be queried,
because the associated components are still missing:
```@example econetd
try # hide
m.trophic.matrix
catch e showerr(e) end # hide
```

Before we add the missing [`Foodweb`](@ref) component,
let us explain that the component addition we did above
actually happened in *two stages*.

### Blueprints Expand into Components

To add a component to a model,
we first need to create a *blueprint* for the component.
A blueprint is a julia value
containing all the data needed to *expand* into a component.
```@example econetd
sp = Species([:hen, :fox, :snake]) # This is a blueprint, useful to later expand into a model component.
```

When you call the [`add!`](@ref) function,
you feed it with a model and a blueprint.
The blueprint is read and expanded within the given model:
```@example econetd
m = Model() # Empty model.
add!(m, sp) # Expand blueprint `sp` into a `Species` component within `m`.
m           # The result is a model with 1 component inside.
```

As we have seen before: once it has been expanded into the model,
you cannot always edit the component data directly.
For instance, the following does not work:
```@example econetd
try # hide
m.species.names[2] = "rhino"
catch e showerr(e) end # hide
```

However, you can always edit the *blueprint*,
then re-expand it later into other models.
```@example econetd
sp.names[2] = :rhino    # Edit one species name within the blueprint.
push!(sp.names, :ficus) # Append a new species to the blueprint.
m2 = Model(sp)          # Create a new model from the modified blueprint.
m2                      # This new model contains the alternate data.
```

Blueprints can get sophisticated.
For instance,
here are various ways to create blueprints for a [`Foodweb`](@ref) component.
```@example econetd
fw = Foodweb(:niche, S = 5, C = 0.2)         # From a random model.
fw = Foodweb([0 1 0; 1 0 1; 0 0 0])          # From an adjacency matrix.
fw = Foodweb([:fox => :hen, :hen => :snake]) # From an adjacency list.
nothing # hide
```

So, although the value `Foodweb` represents a component,
you can *call* it to produce blueprints expanding into this component.
In Julia linguo:
`Foodweb` is a singleton functor value
that forwards its calls to actual blueprint constructors.

Instead of calling the `Foodweb` component as a functor,
you can be more explicit by calling the blueprint constructors directly:
```@example econetd
fw = Foodweb.Matrix([0 1 0; 1 0 1; 0 0 0])
fw = Foodweb.Adjacency([:fox => :hen, :hen => :snake])
nothing # hide
```

Here, `Foodweb.Matrix` and `Foodweb.Adjacency`
are two different types of blueprints providing the component `Foodweb`.
The call to `Fooweb(:niche, ...)` yields a random `Foodweb.Matrix` blueprint.

If you want to test the component,
but you don't want to loose the original model,
you can keep a safe [`copy`](@ref) of it
before you actually expand the blueprint:
```@example econetd
base = copy(m) # Keep a safe, basic, incomplete version of the model.
add!(m, fw)    # Expand the foodweb into a new component within `m`: `base` remains unchanged.
nothing # hide
```

A shorter way to do so is to directly use julia's `+` operator,
which always leaves the original model unchanged
and creates an augmented copy of it:
```@example econetd
m = base + fw # Create a new model `m` with a Foodweb inside, leaving model `base` unchanged.
```

Separating blueprints creation from final components expansion
gives you flexibility when creating your models.
Blueprints can either be thrown after use,
or kept around to be modified and reused without limits.

## Model Constraints

Of course, you cannot expand blueprints into components
that would yield inconsistent models:
```@example econetd
base = Model(Species(3)) # A model a with 3-species compartment.
try # hide
global m # hide
m = base + Foodweb([0 1; 0 0]) # An adjacency matrix with only 2×2 values.
catch e showerr(e) end # hide
```

Components cannot be *removed* from a model,
because it could lead to inconsistent model values.
Components cannot either be *duplicated* or *replaced* within a model:
```@example econetd
m = Model(Foodweb(:niche, S = 5, C = 0.2))
try # hide
global m # hide
m += Foodweb([:a => :b]) # Nope: already added.
catch e showerr(e) end # hide
```

In other terms: models can only be build *monotonically*.  
If you ever feel like you need
to "change a component" or "remove a component" from a model,
the correct way to do so is to construct a new model
from the blueprints and/or the other base models you have kept around.

Components also *require* each other:
you cannot specify trophic links efficiency in your model
without having first specified what trophic links are:
```@example econetd
m = Model(Species(3))
try # hide
global m # hide
m += Efficiency(4)
catch e showerr(e) end # hide
```

## Bringing Blueprints

To help you not hit the above problem too often,
some blueprints take advantage of the fact
that they contain the information needed
to *also* expand into some of the components they require.
Conceptually, they carry the information needed
to *bring* smaller blueprints within them.


### *Imply*

For instance, the following blueprint for a foodweb
contains enough information to expand into both a [`Foodweb`](@ref) component,
*and* the associated [`Species`](@ref) component if needed:
```@example econetd
fw = Foodweb([1 => 2, 2 => 3]) # Species nodes can be inferred from this blueprint..
m = Model(fw) # .. so a blank model given only this blueprint becomes equiped with the 2 components.
```

As a consequence,
it is not an error to expand the `Foodweb.Adjacency` blueprint
into a model not already having a `Species` compartment.
We say that the `Foodweb.Adjacency` blueprint
*implies* a blueprint for component `Species`.

If you need more species in your model than appear in your foodweb blueprint,
you can still explicitly provide a larger `Species` blueprint
before you add the foodweb:
```@example econetd
m = Model(Species(5), Foodweb([1 => 2, 2 => 3])) # A model with 2 isolated species.
```

In other words, *implied* blueprints are only expanded if needed.

### *Embed*

Some blueprints, on the other hand, explicitly *embed* other blueprints.
For instance, the [`LinearResponse`](@ref)
embeds both [`ConsumptionRate`](@ref)
and [`ConsumersPreference`](@ref) "sub-blueprints":
```@example econetd
lin = LinearResponse()
```

So a model given this single blueprint can expand with 3 additional components.

```@example econetd
m += lin
```

The difference between *embedding* and *implying*
is that the *embedded* sub-blueprints are always expanded.
The direct consequence is that they *do* conflict with existing components:
```@example econetd
m = Model(fw, ConsumptionRate(2)) # This model already has a consumption rate.
try # hide
global m # hide
m += lin # So it is an error to bring another consumption rate with this blueprint.
catch e showerr(e) end # hide
```

This protects you from obtaining a model value with ambiguous consumption rates.

To prevent the [`ConsumptionRate`](@ref) from being brought,
you need to explicitly remove it from the blueprint embedding it:
```@example econetd
lin.alpha = nothing # Remove the brought sub-blueprint.
lin = LinearResponse(alpha = nothing) # Or create directly without the embedded blueprint.
m += lin # Consistent model obtained.
```

# Using the Default Model

Building a model from scratch can be tedious,
because numerous components are required
for the eventual simulation to take place.

Here is how you could do it
with only temporary blueprints immediately dismissed:
```@example econetd
m = Model(
  Foodweb([:a => :b, :b => :c]),
  BodyMass(1),
  MetabolicClass(:all_invertebrates),
  BioenergeticResponse(),
  LogisticGrowth(),
  Metabolism(:Miele2019),
  Mortality(0),
)
nothing # hide
```

Here is how you could do it
with blueprints that you would keep around
to later reassemble into other models:
```@example econetd
# Basic blueprints saved into variables for later edition.
fw = Foodweb([:a => :b, :b => :c])
bm = BodyMass(1)
mc = MetabolicClass(:all_invertebrates)
be = BioenergeticResponse()
lg = LogisticGrowth()
mb = Metabolism(:Miele2019)
mt = Mortality(0)

# One model with all the associated components.
m = Model() + fw + bm + mc + be + lg + mb + mt
nothing # hide
```

If this is too tedious,
you can use the [`default_model`](@ref) function instead
to automatically create a model with all (or most) components
required for simulation.
The only mandatory argument to [`default_model`](@ref)
is a [`Foodweb`](@ref) blueprint:
```@example econetd
fw = Foodweb([:a => :b, :b => :c])
m = default_model(fw)
```

But you can feed other blueprints into it
to fine-tweak just the parameters you want.
```@example econetd
m = default_model(fw, BodyMass(Z = 1.5), Efficiency(.2))
(m.body_mass, m.efficiency)
```

The function [`default_model`](@ref) tries hard
to figure the default model you expect
based on the only few blueprints you input.
For instance, it assumes that you need
a different type of functional response
if you input a [`Temperature`](@ref) component,
and temperature-dependent allometry rates:
```@example econetd
m = default_model(fw, Temperature(220))
```

Or if you wish to explicitly represent [`Nutrients`](@ref)
as a separate nodes compartment in your ecological network:
```@example econetd
m = default_model(fw, Nutrients.Nodes(2))
```

## /!\ Find fresh example snippets /!\

This page of the manual is up-to-date with the latest version of the package,
but not the other pages yet.  
However, you will already (and always) find up-to-date examples of manipulating
models/blueprints/components under the [`test/user`](../../test/user) folder.
Have a look in there to get familiar with all the package features ;)

If you were accustomed to a former version of the package,
also take a look at our [`CHANGELOG.md`](../../CHANGELOG.md).

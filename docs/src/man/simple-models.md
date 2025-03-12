# Build Simple Models

We represent community models as objects of type [`Model`](@ref).
The [`Model`](@ref) contains all the parameters needed to simulate the dynamics of a community of species.
These parameters correspond mostly to species traits and interaction strengths.
They can be set up manually or generated automatically from a [`Foodweb`](@ref).

## Create a Default Model

The [`Model`](@ref) contains many parameters, and it can be cumbersome to set them all up manually.
Therefore, we provide a function `default_model` that generates a model with default parameters to ease the process.
The function [`default_model`](@ref) generates a model from a [`Foodweb`](@ref).

```@setup econetd
using EcologicalNetworksDynamics
m = default_model(Foodweb([3 => 2, 2 => 1]))
```

By default, the predator functional response is classic and the producer growth is logistic.
Moreover, species traits are taken from [Miele et al. (2019)](https://doi.org/10.1371/journal.pcbi.1007269).
For details on the default parameters, see the [Parameter Table](@ref).

If you want to change the default parameters, you can do so by passing the corresponding component as an argument to the `default_model` function.
For instance, by default species body masses
are set so that the predator body mass is 10 times the prey body mass.

```@example econetd
m1 = default_model(Foodweb([3 => 2, 2 => 1]))
m1.body_mass
```

But let's say you want to set the body mass of all species to 1.5, then you can do:

```@example econetd
m2 = default_model(Foodweb([3 => 2, 2 => 1]), BodyMass(1.5))
m2.body_mass
```

You can also change the default predator-prey body mass ratio to set up species body masses:

```@example econetd
m3 = default_model(Foodweb([3 => 2, 2 => 1]), BodyMass(; Z = 5))
m3.body_mass
```

In the example above the body mass of the predator is 5 times the body mass of the prey, starting with a body mass of 1 for the primary producer.

## Access the Model Data

The parameters held by the model can be accessed via the various model properties,
with functions named `m.<parameter_name>` where `m` is the model object:

```@example econetd
m.hill_exponent
```

```@example econetd
m.body_mass
```

```@example econetd
m.efficiency
```

The properties of the model can be viewed with:

```@example econetd
properties(m)
```

## Change the Model Data

Some parameters can be modified after the model was created
with `m.<x> = value`.
However, not all parameters can be modified in this way for consistency issues.
For instance, many parameters are derived from body masses, therefore changing the body masses would make the model inconsistent.

```@example econetd
# OK: terminal data can be changed.
m.hill_exponent = 2.1

try # hide
# Not OK: this would make the rest of the model data inconsistent.
m.body_mass = [1, 2, 3]
catch err; print(stderr, "ERROR: "); showerror(stderr, err); end # hide
```

If you need a model with different values for non-modifiable properties,
you need to build a new model with the values you desire.

## Create Your Own Model Manually

It is also possible to create a model manually by adding the components one by one.
First, create an empty model:

```@example econetd
m = Model()
```

Then add your components one by one.
Note that you have to add the components in the right order, as some components depend on others.
Moreover, some components are mandatory.
Specifically, you need to provide a food web, species metabolic classes, body masses,
a functional response, metabolic rates and a producer growth function.

```@example econetd
m = Model()
m += Foodweb([3 => 2, 2 => 1])
m += BodyMass(; Z = 3)
m += MetabolicClass(:all_invertebrates)
m += ClassicResponse(; h = 2)
m += LogisticGrowth(; r = 1, K = 10)
m += Metabolism(:Miele2019)
m += Mortality(0)
```

Now we have a model ready to be simulated.
We explain how to do so in the section [Simulate the Model](@ref).
But, first we explain how to create more sophisticated models in the following section [Build Advanced Models](@ref).

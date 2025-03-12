# Quick start

This section presents a minimal example
to discover how EcologicalNetworksDynamics works.
The best is to follow this tutorial by pasting the following code blocks in your Julia terminal.

The first step is to create the structure of the trophic interactions.

```@example quickstart
ENV["GKSwstype"] = "100" # See https://documenter.juliadocs.org/stable/man/syntax/ # hide
using EcologicalNetworksDynamics, Plots
fw = Foodweb([1 => 2, 2 => 3]) # 1 eats 2, and 2 eats 3.
```

Then, you can generate the parameter of the model
(species rates, interaction parameters, etc.) with

```@example quickstart
m = default_model(fw)
```

Parameters can be accessed as follow `m.<parameter_name>`,
for instance, to access species metabolic rates

```@example quickstart
m.metabolism
```

We see that while consumers (species 1 and 2) have a positive metabolic rate,
producer species (species 3) have a null metabolic rate.
The list of all model properties can be accessed with

```@example quickstart
properties(m)
```

Once our model is ready, we can simulate its dynamic.
To do so, we need first to specify species initial biomasses.

```@example quickstart
B0 = [0.1, 0.1, 0.1] # The 3 species start with a biomass of 0.1.
t = 100 # The simulation will run for 100 time units.
out = simulate(m, B0, t)
```

Lastly, we can plot the biomass trajectories using the `plot` functions of [Plots](https://docs.juliaplots.org/latest/).

```@example quickstart
plot(out)
savefig("quickstart.png") # hide
nothing # hide
```

![Quickstart plot](quickstart.png)

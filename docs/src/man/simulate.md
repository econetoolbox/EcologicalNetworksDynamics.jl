# Simulate the Community Dynamics

Previous sections tackled how to create a model representing the desired ecological community.
We now explain how to simulate the dynamics of this community.
In short, we provide a function `simulate` that takes a model and a time interval as input and returns the temporal trajectory of the community.
This function uses the [DifferentialEquations](https://docs.sciml.ai/DiffEqDocs/stable/) package to solve the system of ordinary differential equations.

## Basic Usage

Let's first illustrate how to simulate a simple community of three species.

```@example econetd
using EcologicalNetworksDynamics, Plots
ENV["GKSwstype"] = "100" # See https://documenter.juliadocs.org/stable/man/syntax/ # hide

foodweb = Foodweb([3 => 2, 2 => 1])
m = default_model(foodweb)
B0 = rand(3) # Vector of initial biomasses.
t = 1_000
sol = simulate(m, B0, t)
```

We can access the solution of the simulation with the output of the `simulate` function.
We list below some useful properties of the solution:

```@example econetd
sol.t # Time steps.
sol.u # Biomasses at each time step.
sol.u[1] # Biomasses of the first time step.
sol.u[end] # Biomasses of the last time step.
```

The solution can be plotted with the `plot` function from the Plots package.

```@example econetd
plot(sol)
savefig("simulation.svg") # hide
nothing # hide
```

![Figure of the simulation](simulation.svg)

The duration of the simulation can be changed with, for instance to reduce the simulation time to 100 time units:

```@example econetd
smaller_t = 100
sol = simulate(m, B0, smaller_t)
sol.t[end] # The last time step.
```

## Callbacks

We will now go through some advanced features of the `simulate` function.
First, the `callback` keyword argument allows specifying a function that will be called at each time step of the simulation.
We provide a built-in callback `extinction_callback` which extinguishes the species whose biomass falls below a given threshold.
This threshold is set by default to `1e-12`, but can be changed.

```@example econetd
foodweb = Foodweb([3 => 1, 2 => 1]) # Two predators feeding on one prey.
m = default_model(foodweb, Metabolism([0, 0.1, 100.0])) # Predator (3) has a too high metabolic rate to survive.
sol = simulate(m, [1, 1, 1], 100_000; callback = nothing) # No callback.
sol[end]
```

```@example econetd
callback = extinction_callback(m, 1e-6)
sol = simulate(m, [1, 1, 1], 100_000; callback) # High extinction threshold.
sol[end]
```

```@example econetd
callback = extinction_callback(m, 1e-12)
sol = simulate(m, [1, 1, 1], 100_000; callback) # Low extinction threshold.
sol[end]
```

Other callback functions are available in the [DiffEqCallbacks](https://docs.sciml.ai/DiffEqCallbacks/stable/) package, and can be used in the same way.

## Choose a Specific Solver

Depending on your needs, you may want to choose a specific solver for the simulation.
As we use the `solve` function of the [DifferentialEquations](https://docs.sciml.ai/DiffEqDocs/stable/) package, we can pass any solver available in this package
(see [the list of available solvers](https://docs.sciml.ai/DiffEqDocs/stable/solvers/ode_solve/)).
Indeed, we allow the user to pass any keyword argument of the `solve` function to the `simulate` function.

```@example econetd
import DifferentialEquations: Tsit5

sol = simulate(m, [1, 1, 1], 1_000; alg = Tsit5())
sol.alg
```

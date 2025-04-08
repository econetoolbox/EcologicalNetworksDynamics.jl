# Stability analysis

This section covers how to analyse the stability of a community once simulated.

To begin we need to utility functions from the companion package.

```@example econetd
using EcoNetDynOutputs # Companion package - stability functions.
```

## Jacobian

Many stability metrics are derived from the Jacobian of the dynamical system.
The most famous one being the resilience, which captures the community
asymptotic recovery rate, that is, how fast the community recovers in the
long-term.

Let's consider a simple community of a consumer feeding on a producer.

```@example econetd
using EcologicalNetworksDynamics

fw = Foodweb([:consumer => :producer])
m = default_model(fw)
```

Before going further, we can check species indices, which is going to 
useful for subsequent steps.

```@example econetd
m.species.index
```

We see that species 1 is the consumer, and species 2 is the producer.
We can simulate the dynamic of this simple model to find its steady-state.

```@example econetd
B0 = [1, 1] # Initial biomass.
sol = simulate(m, B0, 1_000)
Beq = sol[end]
```

At steady-state the consumer has a biomass near 0.39, 
and the producer has a biomass near 0.18.

We can compute the Jacobian of this system.
The `jacobian` function requires two arguments:
- `m` specifying the model
- `B` the vector of biomass where to evaluate the jacobian
Most of the time `B` is going to be species biomass at equilibrium,
as the Jacobian is particularly useful and relevant to perform the stability analysis near an equilibrium.

In our setting, we have

```@example econetd
j = jacobian(m, Beq)
```

We can compute the resilience of the system with


```@example econetd
resilience(j)
```

We expect a negative value, as we have seen that the equilibrium is stable.

Another common stability metric derived from the Jacobian, that is
increasingly used is the community reactivity.

```@example econetd
reactivity(j)
```

A positive value means that the system can go away from its equilibrium after a
disturbance, before eventually recovering.

# Build Advanced Models

In the previous section, we showed how to create relatively simple models.
Here, we explain how to build more sophisticated models by modifying or adding the following features:

  - [Functional Responses](@ref)
  - [Non-Trophic Interactions](@ref)
  - [Temperature Scaling](@ref)
  - [Explicit Nutrient Dynamics](@ref)
  - [Competition Between Producers](@ref)

## Functional Responses

By default, the functional response is classic as in [Yodzis and Innes, 1992](https://doi.org/10.1086/285380), that is parameterized by the attack rate and the handling time.
We write below the corresponding dynamical system:

```math
\frac{dB_i}{dt} = g(B_i)
    + B_i \sum_{j \in \{ \text{res.} \}} e_{ij} F_{ij}
    - \sum_{j \in \{ \text{cons.} \}} B_j F_{ji}
    - x_i B_i
```

```math
F_{ij} = \frac{1}{m_i} \cdot
    \frac{\omega_{ij} a_{ij} B_j^h}{1 + c_i B_i
    + h_t \sum_{k \in \{ \text{res.} \}} \omega_{ik} a_{ik} B_k^h}
```

with:

  - ``\omega_{ij}`` preference of consumer ``i`` on resource ``j``
  - ``c_i`` the intensity of intraspecific predator interference in consumer ``i``
  - ``h`` the hill-exponent
  - ``a_{ij}`` the attack rate of consumer ``i`` on resource ``j``
  - ``h_t`` the handling time
  - ``m_i`` the body mass of consumer ``i``

The parameters of the functional response can be customized.
For example, the default hill exponent is 2 (type III functional response).

```@example econetd
using EcologicalNetworksDynamics
fw = Foodweb([2 => 1])
m = default_model(fw)
m.hill_exponent
```

But we can change its value, for instance to 1:

```@example econetd
m.hill_exponent = 1
```

Above, we changed the value after the model was created.
But this value can also be set when the model is created:

```@example econetd
m = default_model(fw, ClassicResponse(; h = 1))
m.hill_exponent
```

Moreover, the model can also be parameterized using the bioenergetic functional response
as in [Williams, Brose and Martinez](https://doi.org/10.1007/978-1-4020-5337-5_2),
that depends on species half-saturation density.

```math
\frac{dB_i}{dt} = g(B_i)
    + B_i \sum_{j \in \{ \text{res.} \}} e_{ij} F_{ij}
    - \sum_{j \in \{ \text{cons.} \}} B_j F_{ji}
    - x_i B_i
```

```math
F_{ij} = \frac{\omega_{ij} B_j^h}{B_0^h + c_i B_i B_0^h
    + \sum_{k \in \{ \text{res.} \}} \omega_{ik} B_k^h}
```

with:

  - ``\omega_{ij}`` preference of consumer `i` on resource `j`
  - ``B_0`` the half-saturation density
  - ``c_i`` the intensity of intraspecific predator interference
  - ``h`` the hill-exponent

To change for the bioenergetic functional response, you can do:

```@example econetd
m = default_model(fw, BioenergeticResponse())
m.half_saturation_density[2] # Consumer half-saturation density.
```

You can also tune the bioenergetic functional response.
For instance, you can change the half-saturation density:

```@example econetd
m = default_model(fw, BioenergeticResponse(; half_saturation_density = 0.1))
m.half_saturation_density[2] # Check that the value is the one we set.
```

## Non-Trophic Interactions

Food webs, and therefore trophic interactions, are at the core of the package.
However, the importance of interactions other than trophic
(hereafter "non-trophic interactions")
such as facilitation or competition, is increasingly recognized.
They can profoundly shape the community dynamics,
and including them or not can drastically change simulation outcomes.
For this reason, we offer the possibility to include non-trophic interactions in food web models.
Four non-trophic interactions can be modeled
as in [Miele et al., (2019)](https://doi.org/10.1371/journal.pcbi.1007269):

  - Competition for space between producers
  - Plant facilitation (e.g. because of nitrogen fixation or seed dispersal)
  - Interference between predators sharing a prey
  - Refuge provisioning for prey

For example, let's compare the dynamics of a plant growing toward its carrying capacity with and without facilitation.
In this simplistic setting, we do not consider trophic interactions,
but only the plant (species 1)

```@example econetd
using Plots
ENV["GKSwstype"] = "100" # See https://documenter.juliadocs.org/stable/man/syntax/ # hide

fw = Foodweb(zeros(Int, 2, 2))
m_no_facilitation = default_model(fw)
B0, t = [0.1], 10
sol_no_facilitation = simulate(m_no_facilitation, B0, t)
A = [0 0; 1 0]
m_facilitation = default_model(fw, Facilitation.Layer(; A))
sol_no_facilitation = simulate(m_no_facilitation, B0, t)
sol_facilitation = simulate(m_facilitation, [0.1], t)
plot(
    sol_no_facilitation;
    xlabel = "Time",
    ylabel = "Biomass",
    idxs = [1],
    label = "without facilitation",
)
plot!(sol_facilitation; idxs = [1], label = "with facilitation")
savefig("facilitation.svg");
nothing; # hide
```

![Figure illustrating facilitation effect](facilitation.svg)

We observe that the plant grows faster with facilitation, as we intuitively expect.

## Temperature Scaling

The metabolic theory of ecology (MTE) describes how species biological rates scale with temperature.
We allow scaling the metabolic rates of species with temperature, following the MTE, as in [Binzer et al. (2016)](https://doi.org/10.1111/gcb.13086).
To do so, we simply have to pass the temperature to the model.

```@example econetd
m = default_model(fw, Temperature(290)) # Note that the temperature is in Kelvin.
```

For example, we can plot the attack rate as a function of temperature:

```@example econetd
fw = Foodweb([2 => 1])
attack_rate = []
T_values = 273.15:1:310.15
for T in T_values
    local m = default_model(fw, Temperature(T))
    push!(attack_rate, m.attack_rate[2, 1])
end
plot(T_values, attack_rate; xlabel = "Temperature (K)", ylabel = "Attack Rate")
savefig("temperature-attack-rate.svg");
nothing; # hide
```

![Figure of attack rate vs temperature](temperature-attack-rate.svg)

## Explicit Nutrient Dynamics

Producer growth dynamics is by default modelled by a logistic growth.
But, we can also model explicit nutrient dynamics given by:

```math
\frac{\mathrm{d} N_l}{\mathrm{d} t} = D_l(S_l - N_l)-\sum^n_{i=1}{c_{li}G_i(N)B_i}
```

Where:

  - ``N_l`` is the concentration of nutrient `l`
  - ``D_l`` is the turnover rate of nutrient `l`
  - ``S_l`` is the supply rate of nutrient `l`
  - ``c_{li}`` is the nutrient concentration of producer `i` in nutrient `l`
  - ``r_i`` is the intrinsic growth rate of producer `i`

Moreover, the producer growth `G_i` is given by:

```math
G_{i}(N) = \min(\frac{N_1}{K_{1i}+N_1}, \dots, \frac{N_l}{K_{li}+N_l}) B_i
```

Where `K_{li}` is the half-saturation constant of producer `i` for nutrient `l`.
For more details, see for instance
[Brose (2008)](https://doi.org/10.1098/rspb.2008.0718).

To implement nutrient dynamics, we have to pass the corresponding component to the model.

```@example econetd
m = default_model(fw, NutrientIntake(1))
m.nutrients.number
```

We can of course change the number of nutrients:

```@example econetd
m = default_model(fw, NutrientIntake(3))
m.nutrients.number
```

We can also change the parameters of the nutrient dynamics, as the supply rate, the concentration, and the nutrient turnover rate:

```@example econetd
m = default_model(fw, NutrientIntake(3; supply = 10.2))
m.nutrients.supply
```

```@example econetd
m = default_model(fw, NutrientIntake(3; turnover = 0.2))
m.nutrients.turnover
```

```@example econetd
m = default_model(fw, NutrientIntake(3; concentration = 0.9))
m.nutrients.concentration
```

Nutrient concentration is a matrix, where rows correspond to producers
and columns to nutrients.

## Competition Between Producers

By default, producers follow logistic growth.

```math
G_i = 1 - \frac{B_i}{K_i}
```

Where $K\_i$ is the carrying capacity of the producer `i`, and `B_i` is its biomass.
But this formulation can be generalized to the case of competition between producers, thereby reading:

```math
G_i = 1 - \frac{\sum_{j=1}^{S} a_{ij} B_j}{K_i}
```

Where `a_{ij}` is the competition coefficient between producer `i` and `j`.
Producer competition can be implemented by modifying the producer growth component of the model.

```@example econetd
foodweb = Foodweb(zeros(Int, 2, 2)) # 2 producers.
g_no_competition = LogisticGrowth(; producers_competition = [1 0; 0 1]) # Default.
```

```@example econetd
g_competition = LogisticGrowth(; producers_competition = [1 0.1; 0.9 1])
```

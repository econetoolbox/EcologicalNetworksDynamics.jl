# Generate Food Webs

Food webs are at the core of this package,
and thus can be generated in various ways depending on your needs.
In the following sections, we will go over the different methods of network generation.
But, first things first, let us see what is inside a [`Foodweb`](@ref).

A [`Foodweb`](@ref) object contains the trophic adjacency matrix `A` filled with 0s and 1s
indicating respectively the absence and presence of trophic interactions.
Rows are consumers and columns resources, thus `A[i,j] = 1` reads "species `i` eats species `j`"

## From an Adjacency Matrix

The most straightforward way to generate a [`Foodweb`](@ref) is to
define your own adjacency matrix (`A`) by hand
and give it to the [`Foodweb`](@ref) method
that will return the corresponding [`Foodweb`](@ref) object.

```@setup econetd
using EcologicalNetworksDynamics
```

```@example econetd
A = [0 0 0; 1 0 0; 0 1 0] # 1 <- 2 <- 3.
foodweb = Foodweb(A)
```

## From an Adjacency List

Sometimes it is more convenient to define the food web using an adjacency list,
because adjacency lists are often more readable than adjacency matrices.
Adjacency lists are a list of pairs, where each pair is a consumer-resource interaction.

For instance, the food web presented in the previous example can be defined as:

```@example econetd
list = [2 => 1, 3 => 2]
foodweb = Foodweb(list)
```

Species can also be named with strings or symbols:

```@example econetd
list = [:eagle => :rabbit, :rabbit => :grass]
foodweb = Foodweb(list)
```

Creating a [`Foodweb`](@ref) from your own adjacency matrix or list is straightforward,
but this is mostly useful for simple and small 'toy systems'.
If you want to work with [`Foodweb`](@ref)s with a large size and a realistic structure,
it is more suitable to create the [`Foodweb`](@ref) using structural models.

## Structural Models

You can generate a [`Foodweb`](@ref) using either the **niche model** or the **cascade model**.

### Niche Model

The niche model requires:

  - `S`: Number of species.
  - Either `C` (connectance) **or** `L` (number of links).

```@example econetd
fw1 = Foodweb(:niche; S = 5, C = 0.2)
fw2 = Foodweb(:niche; S = 5, L = 5)
```

### Cascade Model

The cascade model requires:

  - `S`: Number of species.
  - `C`: Connectance.

```@example econetd
fw3 = Foodweb(:cascade; S = 5, C = 0.2)
```

### Tolerance and Constraints

By default, the generated [`Foodweb`](@ref) ensures the number of links (`L`) or
connectance (`C`) falls within a **10% tolerance** of the specified value:

  - If `L = 20`, the output will have **18–22 links**.
  - If `C` is given, the tolerance is similarly applied to the connectance.

#### Example: Default Tolerance

```@example econetd
fw4 = Foodweb(:niche; S = 15, L = 15)
13 <= sum(fw4.A) <= 18  # 15 links ±10% (rounded)  
```

#### Custom Tolerance

Override defaults with `tol_L` (for `L`) or `tol_C` (for `C`):

```@example econetd
fw5 = Foodweb(:niche; S = 15, L = 15, tol_L = 0)  # Strictly 15 links  
sum(fw5.A) == 15
```

### Advanced Control

#### Trophic Structure Validation

By default, the model:

  - **Rejects disconnected species** (`reject_if_disconnected = true`).
  - **Allows cycles** (`reject_cycles = false`; e.g., cannibalism).

##### Options:

```@example econetd
fw6 = Foodweb(:niche; S = 15, L = 15, reject_cycles = false)  # Allow cycles  
fw7 = Foodweb(:niche; S = 15, L = 15, reject_if_disconnected = false)  # Allow disconnected species  
```

#### Algorithm Iterations

The default maximum iterations (`10^5`) can be increased for challenging
parameter combinations (e.g., near boundary conditions or strict tolerances):

```@example econetd
fw8 = Foodweb(:niche; S = 15, L = 15, max_iterations = 10^6)
```

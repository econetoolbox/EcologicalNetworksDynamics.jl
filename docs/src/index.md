```@meta
CurrentModule = EcologicalNetworksDynamics
```

# EcologicalNetworksDynamics

EcologicalNetworksDynamics is a package designed to simulate species biomass dynamics
in ecological networks.
These networks can contain either trophic interactions only (food webs),
or trophic interactions plus various non-trophic interactions (multiplex networks).
We provide functions to generate food web structure from well-known structural models as the niche model.
We designed EcologicalNetworksDynamics so that it is easy to use for non-specialists,
while remaining flexible for more experienced users who would like to tweak the model.

## Before you start

Before anything else, to use EcologicalNetworksDynamics you have to install Julia.
For that go to the [official download page](https://julialang.org/downloads/).
Once you have successfully installed Julia,
you can install the package by running from a Julia terminal:

```julia
using Pkg
Pkg.add("EcologicalNetworksDynamics")
```

To check that the package installation went well, you can load the package:

```julia
using EcologicalNetworksDynamics
```

You can now create a simple food web with:

```julia
Foodweb([1 => 2])
```

This is a two-species food web in which species 1 eats species 2.

## Learning EcologicalNetworksDynamics

The [Quick Start](@ref) page shows how to simulate biomass dynamics in a simple food web.
The rest of the guide provides a step by step introduction to the package features,
from the generation of the network structure to the simulation of the biomass dynamics.
At each step, we detail how the model can be customized at your will.
Lastly, the Tutorials section contains realistic use-cases of EcologicalNetworksDynamics.

## Getting help

During your journey learning EcologicalNetworksDynamics you might encounter issues.
If so the best is to open an issue on the
[GitHub page of EcologicalNetworksDynamics](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues).
To ensure that we can help you efficiently,
please provide a short description of your problem, and a minimal example to reproduce the error you encountered.

## How can I contribute?

The easiest way to contribute is to
[open an issue](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues)
if you spot a bug, a typo or can't manage to do something.
Another way is to fork the repository,
start working from the `dev` branch,
and when ready, submit a pull request.
The contribution guidelines are detailed
[here](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/blob/dev/CONTRIBUTING.md).

## Citing

Please cite EcologicalNetworksDynamics
if you use it in research, teaching, or other activities.

  - **TODO: add paper DOI**
  - package: [DOI:10.5281/zenodo.14609708](https://zenodo.org/doi/10.5281/zenodo.14609708)

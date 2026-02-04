<p align="center" width="100%">
    <img height="150" src="https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/blob/doc/docs/src/assets/logo-and-name.svg#gh-light-mode-only">
    <img height="150" src="https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/blob/doc/docs/src/assets/logo-and-name-dark.svg#gh-dark-mode-only">
</p>

EcologicalNetworksDynamics is a Julia package that simulates species biomass dynamics
in ecological networks.
EcologicalNetworksDynamics makes things easy for beginners
while remaining flexible for adventurous or experienced users
who would like to tweak the model.

[![docs](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/actions/workflows/docs.yml/badge.svg?branch=doc)](https://econetoolbox.github.io/EcologicalNetworksDynamics.jl/)
[![tests](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/actions/workflows/tests.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](http://www.gnu.org/licenses/gpl-3.0)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.14609708.svg)](https://doi.org/10.5281/zenodo.14609708)

## Before you start

Before anything else, to use EcologicalNetworksDynamics you have to [install Julia](https://julialang.org/downloads/).
Note that the package is **compatible with Julia 1.10 and higher**,
therefore please make sure you have a recent enough version of Julia.
Once you have successfully installed Julia, you can check the version
by typing in a Julia terminal

```julia
VERSION >= v"1.10"
```

If the output is `true`, you are good to go.
Otherwise, you will have to download a newer version of Julia.
Once you have ensured that Julia is properly installed,
you can install the package by running in a Julia terminal

```julia
using Pkg
Pkg.add("EcologicalNetworksDynamics")
```

> [!TIP]
> If the package cannot be installed because of incompatible dependencies
> (for example, if you have already an old package installed that requires old versions of some dependencies),
> we advise you to create a fresh environment by running
>
> ```julia
> using Pkg
> Pkg.activate("your_environment_name")
> Pkg.add("EcologicalNetworksDynamics")
> ```
>
> By doing so, you will avoid conflicts with other packages.

To check that the package installation went well,
create a simple food web with

```julia
using EcologicalNetworksDynamics
Foodweb([1 => 2]) # Species 1 eats species 2.
```

## Learning EcologicalNetworksDynamics

The [Quick start] page shows
how to simulate biomass dynamics in a simple food web.
The rest of the [Guide] provides a step by step introduction
to the package features,
from the generation of the network structure
to the simulation of the biomass dynamics.
At each step, we detail how the model can be customized at your will.

[Quick start]: https://econetoolbox.github.io/EcologicalNetworksDynamics.jl/man/quickstart/
[Guide]: https://econetoolbox.github.io/EcologicalNetworksDynamics.jl/

## Getting help

During your journey learning EcologicalNetworksDynamics,
you might encounter issues.
If so, the best is to open [an issue].
To ensure that we can help you efficiently,
please provide a short description of your problem
and a minimal example to reproduce the error you encountered.

[an issue]: https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues

## How can I contribute?

The easiest way to contribute is to [open an issue]
if you spot a bug, a typo or can't manage to do something.
Another way is to fork the repository,
start working from the `dev` branch,
and when ready, submit a pull request.
The contribution guidelines are detailed
[here](https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/blob/dev/CONTRIBUTING.md).

[open an issue]: https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues

## Citing

Please mention `EcologicalNetworksDynamics.jl`
if you use it in research, teaching, or other activities.
To cite the package, please refer to the associated
[paper](https://doi.org/10.1111/2041-210X.14497).


## Acknowledgments

`EcologicalNetworksDynamics.jl` benefited from
the Montpellier Bioinformatics Biodiversity platform (MBB)
supported by the LabEx CeMEB,
an ANR "Investissements d'avenir" program (ANR-10-LABX-04-01),
and from UKRI-NERC grants R/154822-11-1 and R/161273-11-1 to APB.

<p align="center" width="100%">
    <img height="75" src="https://www.ukri.org/wp-content/uploads/2022/03/ukri-nerc-square-logo.png">
    <img height="75" src="https://www.cnrs.fr/sites/default/files/logo/logo.svg">
    <img height="75" src="https://mbb.cnrs.fr/mbb.png">
    <img height="75" src="https://isem-evolution.fr/wp-content/uploads/2020/10/LOGO_ISEM.svg">
</p>

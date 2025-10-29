"""
Build upon Networks to generate efficient differential code.
In this module, we assume that a Network is available
with all the relevant data correctly stored inside,
and we start providing mechanistic *meaning* to this data.

Mostly this is about generating ad-hoc pieces of code,
and then assemble them into a differential function to feed the solver with.
It is okay to spend resources at generation time,
but we are aiming at __maximum efficiency__ for the code generated here,
as the differential is going to be *much* called by the solver,
and constitutes the typical bottleneck of simulations.

A few design axioms:

  - Don't allocate within the differential.
  - Don't waste cycles and memory for storing zeroes, adding zeroes, multiplying zeroes etc.
  - Use straightforward O(1) offset-indexing with integers wherever needed.
  - Facilitate CPU cache hits by keeping data close if involved in close calculations.
  - Use straightforward linear loops over contiguous data: avoid index-chasing.
  - Avoid branching, especially unpredictable.
  - Using redundant/copied data is OK if it enforces the above.
  - Once set, any implementation change must be backed by performance measures.

To avoid frequent recompiling, the generated will be cached,
and it should not depend on the number of nodes in the network,
webs topologies or values in associated data,
unless it unlocks measurable performance gains in degenerated cases.

Every piece of code is generated along with:

  - The input data required for it to run.
  - The (unhygienic) variable names used inside,
    to avoid clashes when assembling pieces together.

There is no system automatically enforcing consistence of the generated code,
which must be careful checked and tested by humans against theoretical expectations.
This module is where most of the biological *meaning* of the package,
with all its quirks and freedom, is implemented,
although blurred by ad-hoc performance tricks.
"""
module Differentials
using ..Networks

# HERE: start with growth and see how it goes.

end

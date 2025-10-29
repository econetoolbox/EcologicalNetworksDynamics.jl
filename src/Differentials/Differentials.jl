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
using Crayons
using MacroTools

include("./errors.jl")

# Naming conventions within generated code.
#   U: current variables values.
#  dU: output derivative.
#  i_root: absolute index node.
#  i_producer: index node within its class (producer).
#  i_producers: absolute index for every node in the class, in canonical order.
#  n_producers: class size.

include("./growth.jl")

"""
Assemble all pieces of code into a `dudt` function.
"""
function generate_dudt(n::Network)

    all_data = Dict{Symbol,Any}()
    function append!(data::NamedTuple)
        for (k, v) in zip(keys(data), values(data))
            # Conflicts are ok with same type and same value.
            if haskey(all_data, k)
                already = all_data[k]
                if typeof(v) !== typeof(already) || v != already
                    generr("Data name conflict:\n\
                            Already there: $k := $already ::$(typeof(already))\n\
                                 Appended: $k := $v ::$(typeof(v))")
                end
            end
            all_data[k] = v
        end
    end

    (growth, data) = generate_growth(n)
    append!(data)

    # Sort data by name for arguments consistency in generated struct constructor.
    all_data = sort!(collect(all_data), by=first)
    fields = (:($k::$(typeof(v))) for (k, v) in all_data)

    code = quote

        mutable struct Data
            $(fields...)
        end

        function dudt!(dU, U, data::Data, time)

            # Destructure input data into variables used within generated pieces.
            (; $(map(first, all_data)...)) = data

            $(growth.args...)

        end

        instance = Data($(map(last, all_data)...))

        (dudt!, Data, instance)
    end

    code

end
export generate_dudt

end

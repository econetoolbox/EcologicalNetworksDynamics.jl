"""
Build upon Networks to generate efficient differential code.
In this module, we assume that a Network is available
with all the relevant data correctly stored inside,
and we start providing mechanistic *meaning* to this data:
parameters to differential equations.

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

const D = Differentials
const I = Iterators

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
Supertype the data structures generated for parametrizing generated simulation code.
"""
abstract type Parameters end


"""
Elementary differential equation to feed the solver with.
Feeds from all variables in the model,
and from a data type that has been generated along
with the associated method code.
"""
dudt!(dU, U, p::Parameters, t) = err("No simulation method generated for $(typeof(p))?")
export dudt!

"""
Assemble all pieces of code
into a generated type and its associated `dudt!` method.
Return a working instance of this type,
corresponding to values in the network.
"""
function codegen(n::Network)

    all_parameters = Dict{Symbol,Any}()
    function append!(parms::NamedTuple)
        for (k, v) in zip(keys(parms), values(parms))
            # Conflicts are ok with same type and same value.
            if haskey(all_parameters, k)
                already = all_parameters[k]
                if typeof(v) !== typeof(already) || v != already
                    generr("Parameter name conflict:\n\
                            Already there: $k := $already ::$(typeof(already))\n\
                                 Appended: $k := $v ::$(typeof(v))")
                end
            end
            all_parameters[k] = v
        end
    end

    (growth, parms) = generate_growth(n)
    append!(parms)

    # Sort data by name for arguments consistency in generated struct constructor.
    all_parameters = sort!(collect(all_parameters); by = first)
    fields = (:($k::$(typeof(v))) for (k, v) in all_parameters)

    # Generate mutable type to hold the required data and keep it up-to date.
    type = quote
        # This name ---v changed to something hygienic if evaluated.
        mutable struct P <: Parameters
            $(fields...)
        end
    end

    # Generate simulation method.
    parnames = map(first, all_parameters)
    code = quote
        function D.dudt!(dU, U, p::P, time)

            # Destructure input data into variables used within generated pieces.
            (; $(parnames...)) = p

            $(growth.args...)

        end
    end

    # The above two pieces of generated code
    # constitute the simulation program for a whole class of models,
    # possibly containing more/less edges/nodes than the one received
    # and/or different data values.
    # Avoid generating/compiling too many julia `structs` and `dudt!` methods,
    # by caching these artifacts.
    # Only models with more/less compartments, variables
    # and/or different functional responses will invalidate this program.
    key = (type, code)
    GenParms = if haskey(GEN_TYPES, key)
        # Skip evaluation if already done.
        GEN_TYPES[key]
    else
        # Otherwise evaluation is needed.
        # Replace type name with a hygienic one for definition in module toplevel scope.
        name = gensym(:Data)
        key = deepcopy(key) # To not mutate it.
        setindexpr!(type, name, 2, 2, 1)
        setindexpr!(code, name, 2, 1, 4, 2)
        eval(quote
            $type
            $code
        end)
        type = invokelatest() do # (just created)
            getfield(D, name)
        end
        GEN_TYPES[key] = type
        GEN_CODE[type] = key
        type
    end

    # Retrieve the generated type to construct and return instance of it.
    invokelatest() do
        GenParms(map(last, all_parameters)...)
    end

end
export codegen

#-------------------------------------------------------------------------------------------
# Module-level collection of generated type names.
const GEN_CODE = Dict{Type,Tuple{Expr,Expr}}() # { name: (type, code) }
# Reverse-index by generated code to not compile it twice.
const GEN_TYPES = Dict{Tuple{Expr,Expr},Type}()

#-------------------------------------------------------------------------------------------

"""
Convenience index into julia expressions
to avoid awkward `.args[i].args[j].args[k].args[l]`..
"""
function getindexpr(x::Expr, i::Int...)
    for i in i
        x = x.args[i]
    end
    x
end, function setindexpr!(x::Expr, v, i::Int...)
    for i in I.take(i, length(i) - 1)
        x = x.args[i]
    end
    x.args[last(i)] = v
end

Base.:(==)(a::P, b::P) where {P<:Parameters} =
    let
        for f in fieldnames(P)
            u, v = getfield(a, f), getfield(b, f)
            u == v || return false
        end
        true
    end

#-------------------------------------------------------------------------------------------
# Display.

function Base.show(io::IO, ::MIME"text/plain", p::Parameters)
    P = typeof(p)
    print(io, "Generated model parameters ($P):")
    for f in fieldnames(P)
        v = getfield(p, f)
        print(io, "\n  $f: $v")
    end
end

"""
Retrieve unanottated, easy to read copy of the underlying generated struct.
"""
function type_code(P::Type{<:Parameters})
    (type, _) = GEN_CODE[P]
    MacroTools.prewalk(rmlines, type)
end
export type_code

"""
Retrieve unanottated, easy to read copy of the underlying generated differential code.
"""
function diff_code(P::Type{<:Parameters})
    (_, code) = GEN_CODE[P]
    MacroTools.prewalk(rmlines, code)
end
export diff_code

type_code(p::Parameters) = type_code(typeof(p))
diff_code(p::Parameters) = diff_code(typeof(p))

end

# Non-trophic interactions layers share many common features
# factorized over the same "multiplex network" API.
module MultiplexApi

using EcologicalNetworksDynamics: Option, SparseMatrix, AD, argerr
const Mx = MultiplexApi

AD.define_aliasing_dict(
    Mx,
    :InteractionDict,
    "interaction layer",
    :interaction,
    (
        :trophic => [:t, :trh],
        :competition => [:c, :cpt],
        :facilitation => [:f, :fac],
        :interference => [:i, :itf],
        :refuge => [:r, :ref],
    ),
)
local InteractionDict # (reassure JuliaLS)

AD.define_aliasing_dict(
    Mx,
    :MultiplexParametersDict,
    "multiplex layer parameter",
    :multiplex_parameter,
    (
        # Required for all layers.
        :topology => [:A, :top, :matrix, :adjacency_matrix],
        :intensity => [:I, :int],
        :functional_form => [:F, :fn],
        # .. but the matrix can alternately be specified by number of links XOR connectance..
        :connectance => [:C, :conn],
        :number_of_links => [:L, :n_links],
        # .. in this case, it requires a symmetry specification.
        :symmetry => [:s, :sym, :symmetric],
    ),
)
local MultiplexParametersDict # (reassure JuliaLS)

# Cheat-sheets to users:
interactions_names() = AD.aliases(InteractionDict)
multiplex_parameters_names() = AD.aliases(MultiplexParametersDict)

# Nest them both into a flexible kwargs API.
multiplex_parameters_types = MultiplexParametersDict(;
    topology = SparseMatrix{Bool},
    intensity = Float64,
    functional_form = Function,
    connectance = Float64,
    n_links = Int64,
    symmetry = Bool,
)
multiplex_types = InteractionDict(
    (i => multiplex_parameters_types for i in AD.standards(InteractionDict))...,
)

AD.define_2D_api(Mx, :Multiplex, InteractionDict, MultiplexParametersDict)

# Perform further checking, adding multiplex semantics.
pstandard(ref) = AD.standardize(ref, MultiplexParametersDict)
expand = AD.expand

# ==========================================================================================
# Default checking for user-facing entry point into the API.
function check_multiplex_arguments(all_parms, implicit_interaction, implicit_parameter)
    given(int, parm) = haskey(all_parms[int], parm) # Check whether a value was given.

    # TODO: 'implicit_parameter' makes no sense in this context..
    # does it even make sense in general?
    for int in AD.standards(InteractionDict)

        # Special-case trophic layer for now:
        # the matrix has already been constructed another way from the foodweb.
        # TODO: this is wrong: the trophic layer actually benefits
        # from *none* of the parameters in MultiplexParametersDict.
        # the "2D" (parm x int) view will likely fall apart in the future.
        # Switch to a nested (int: parms), with possible transversal 2D input just when it's
        # possible.
        if int == :trophic
            for parm in [:sym, :A, :L, :C]
                if given(int, parm)
                    (arg, _) = all_parms[int][parm]
                    argerr("No need to specify $(pstandard(parm)) parameter \
                            for the trophic layer ($(expand(arg))) \
                            since the adjacency matrix \
                            is already specified in the foodweb.")
                end
            end
            continue
        end

        # Another special-case.
        if int == :interference
            if given(int, :F)
                (arg, fn) = all_parms[:interference][:F]
                argerr("The interference layer \
                        needs not be parametrized with a functional form, \
                        but one has been specified as $(expand(arg)): $(repr(fn)).")
            end
        end

        # There are several ways to specify A, forbid ambiguous specifications.
        A_specs = [all_parms[int][parm] for parm in [:A, :C, :L] if given(int, parm)]
        if length(A_specs) > 1
            x, y = (
                begin
                    p, P = (expand(arg), pstandard(arg.i))
                    "$P ($p)"
                end for (arg, _) in A_specs
            )
            argerr("Ambiguous specifications for $int matrix adjacency: \
                    both $x and $y have been specified. \
                    Consider removing one.")
        end

        # Don't specify both symmetry and an explicit matrix.
        if given(int, :sym) && given(int, :A)
            s, A = (expand(all_parms[int][p][1]) for p in (:sym, :A))
            argerr("Symmetry has been specified \
                    for $int matrix adjacency ($s) \
                    but the matrix has also been explicitly given ($A). \
                    Consider removing symmetry specification.")
        end

        # Don't specify symmetry without a mean to construct a matrix.
        if (given(int, :sym) && !given(int, :L) && !given(int, :C))
            s = expand(all_parms[int][:sym][1])
            c, n = (
                if isnothing(implicit_interaction) && isnothing(implicit_parameter)
                    short = AD.shortest(p, MultiplexParametersDict)
                    "$(short)_$(int)"
                else
                    "$p"
                end for p in (:connectance, :n_links)
            )
            argerr("Symmetry has been specified \
                    for $int matrix adjacency ($s) \
                    but it is unspecified \
                    how the matrix is supposed to be generated. \
                    Consider specifying connectance \
                    (eg. with '$(c)') \
                    or the number of desired links \
                    (eg. with '$(n)').")
        end

    end

    # Parameters ready for use: don't forget to check further against current model value.
end

end

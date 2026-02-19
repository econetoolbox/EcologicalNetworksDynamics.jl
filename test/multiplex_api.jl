module TestMultiplexApi

using EcologicalNetworksDynamics.MultiplexApi

using Test
import Main: @argfails

# Shorten argument parser names.
nocontext(; kwargs...) = parse_multiplex_arguments(kwargs)
with_parm(p; kwargs...) = parse_interaction_for_multiplex_parameter(p, kwargs)
with_int(i; kwargs...) = parse_multiplex_parameter_for_interaction(i, kwargs)

@testset "Multiplex API" begin

    # Test semantic guards: constraints regarding the arguments *meaning*.

    # The same check is performed regardless of the input type,
    # although the message does reflect the input type.
    @argfails(
        nocontext(trophic = (sym = true,)),
        "No need to specify symmetry parameter for the trophic layer \
         ('sym' within a 'trophic' argument) \
         since the adjacency matrix is already specified in the foodweb.",
    )
    @argfails(
        nocontext(sym = (trophic = true,)),
        "No need to specify symmetry parameter for the trophic layer \
         ('trophic' within a 'sym' argument) \
         since the adjacency matrix is already specified in the foodweb.",
    )
    @argfails(
        nocontext(sym_t = true),
        "No need to specify symmetry parameter for the trophic layer \
         ('sym_t' argument) \
         since the adjacency matrix is already specified in the foodweb.",
    )
    @argfails(
        with_int(:trophic; sym = true),
        "No need to specify symmetry parameter for the trophic layer \
         ('sym' argument) \
         since the adjacency matrix is already specified in the foodweb.",
    )
    @argfails(
        with_parm(:sym; trophic = true),
        "No need to specify symmetry parameter for the trophic layer \
         ('trophic' argument) \
         since the adjacency matrix is already specified in the foodweb.",
    )

    # Overspecified adjacency matrix.
    @argfails(
        with_int(:refuge; L = 5, C = 8),
        "Ambiguous specifications for refuge matrix adjacency: \
         both connectance ('C' argument) \
         and number_of_links ('L' argument) \
         have been specified. Consider removing one.",
    )
    @argfails(
        nocontext(; A_refuge = [0 0;], L = (r = 5,)),
        "Ambiguous specifications for refuge matrix adjacency: \
         both topology ('A_refuge' argument) \
         and number_of_links ('r' within a 'L' argument) \
         have been specified. Consider removing one.",
    )

    @argfails(
        nocontext(; sym = (refuge = true,), A_r = [0 0;]),
        "Symmetry has been specified for refuge matrix adjacency \
         ('refuge' within a 'sym' argument) \
         but the matrix has also been explicitly given \
         ('A_r' argument). \
         Consider removing symmetry specification.",
    )
    @argfails(
        with_int(:r; sym = true, A = [0 0;]),
        "Symmetry has been specified for refuge matrix adjacency \
         ('sym' argument) \
         but the matrix has also been explicitly given \
         ('A' argument). \
         Consider removing symmetry specification.",
    )

    # Underspecified adjacency matrix.
    @argfails(
        nocontext(; sym = (refuge = true,)),
        "Symmetry has been specified for refuge matrix adjacency \
         ('refuge' within a 'sym' argument) \
         but it is unspecified how the matrix is supposed to be generated. \
         Consider specifying connectance \
         (eg. with 'C_refuge') \
         or the number of desired links \
         (eg. with 'L_refuge').",
    )
    @argfails(
        with_int(:r; sym = true),
        "Symmetry has been specified for refuge matrix adjacency \
         ('sym' argument) \
         but it is unspecified how the matrix is supposed to be generated. \
         Consider specifying connectance \
         (eg. with 'connectance') \
         or the number of desired links \
         (eg. with 'n_links').",
    )

end

end

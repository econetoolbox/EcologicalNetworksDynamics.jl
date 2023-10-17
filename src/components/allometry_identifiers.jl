# JuliaLS incorrectly spits "missing refs" lints wrt generated allometry api identifiers.
# Include this no-op file to fix these lints where needed.

#! format: off
@static if (false)
    include("../AliasingDicts/AliasingDicts.jl")
    using .AliasingDicts
    (local
         AllometricParametersDict,
         Allometry,
         AllometryDict,
         MetabolicClassDict,
         parse_allometric_parameter_for_metabolic_class,
         parse_allometry_arguments,
         parse_metabolic_class_for_allometric_parameter,

         var"")
end
#! format: on

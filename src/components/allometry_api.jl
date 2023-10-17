# Allometric rates and their relation to temperature
# are useful to calculate default values for numerous biorates
# from species body masses M with the formulae:
#
#  x_i  = a * M_i^b           (for nodes)
#  x_ij = a * M_i^b * M_j^c   (for edges)
#
# The values of a, b and c differ for every metabolic class.
#
# This is set up with a 2D nested aliased API
# crossing metabolic class with rates and their roles,
# and the 2D nested aliased dict is part of various biorates blueprints.
module AllometryApi

using ..AliasingDicts
include("./allometry_identifiers.jl")

# Convenience shorter aliases.
@aliasing_dict(
    MetabolicClassDict,
    "metabolic class",
    :metabolic_class,
    [:producer => (:p, :prod), :invertebrate => (:i, :inv), :ectotherm => (:e, :ect)],
)
export MetabolicClassDict

@aliasing_dict(
    AllometricParametersDict,
    "allometric parameter",
    :allometric_parameter,
    [:prefactor => (:a,), :source_exponent => (:b,), :target_exponent => (:c,)],
)
export AllometricParametersDict

# Export aliases cheat-sheets to users:
metabolic_class_names() = AliasingDicts.aliases(MetabolicClassDict)
allometric_parameters_names() = AliasingDicts.aliases(AllometricParametersDict)
export metabolic_class_names, allometric_parameters_names

# Only real values.
inner = AllometricParametersDict(
    (parm => Float64 for parm in AliasingDicts.standards(AllometricParametersDict))...,
)
allometry_types = MetabolicClassDict(
    (mc => inner for mc in AliasingDicts.standards(MetabolicClassDict))...,
)
@prepare_2D_api(Allometry, MetabolicClassDict, AllometricParametersDict)
export parse_allometry_arguments
export parse_metabolic_class_for_allometric_parameter
export parse_allometric_parameter_for_metabolic_class

function check_allometry_arguments(all_parms, implicit_metabolic_class, implicit_parameter)
    # Nothing particular to check in general (yet).
end

# ==========================================================================================
# Display the 1D or 2D nested dicts
# that will be exposed in blueprints.

const Allometry = AllometryDict{Float64}
export Allometry

end

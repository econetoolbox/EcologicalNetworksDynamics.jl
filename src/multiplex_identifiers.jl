# Stupid shenanigans to trick JuliaLS into correctly finding references.
# and not clutter further code with "missing reference" warnings.
# All this code does nothing when actually executed.
# Its sole purpose is to solve these incorrect lints.


#! format: off
if (false)
    (
        local
        InteractionDict,
        Multiplex,
        MultiplexArguments,
        MultiplexDict,
        MultiplexParametersDict,
        TrackedMultiplexParameterDict,
        parse_interaction_for_multiplex_parameter,
        parse_multiplex_arguments,
        parse_multiplex_parameter_for_interaction,

        var""
 )
end
#! format: on

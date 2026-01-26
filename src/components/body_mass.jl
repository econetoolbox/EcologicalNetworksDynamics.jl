# Set or generate body masses for every species in the model.

# (reassure JuliaLS)
(false) && (local BodyMass, _BodyMass)

define_node_data_component(
    EN,
    :M,
    :species,
    :Species,
    :body_mass,
    :BodyMass;
    check_value = (>=(0.0), "Not a positive value."),
    #---------------------------------------------------------------------------------------
    # One extra blueprint to build from trophic levels.
    Blueprints = quote
        Foodweb = $Foodweb

        mutable struct Z <: Blueprint
            Z::Float64
        end
        @blueprint Z "trophic levels" depends(Foodweb)
        export Z

        function F.late_check(_, bp::Z)
            (; Z) = bp
            Z >= 0 || checkfails("Cannot calculate body masses from trophic levels \
                                  with a negative value of Z: $Z.")
        end

        function F.expand!(raw, bp::Z)
            A = @ref raw.A
            M = Internals.compute_mass(A, bp.Z)
            expand_from_vec!(raw, M)
        end

    end,
)

function (::_BodyMass)(; Z = nothing)
    isnothing(Z) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
    BodyMass.Z(Z)
end

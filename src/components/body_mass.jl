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
    check_value = (>=(0.0), "not a positive value"),
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
            level = @ref raw.trophic.level
            M = read(level) do level
                bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
            end
            expand_from_vector!(raw, M)
        end

    end,
)

# Community convenience alias.
@alias body_mass M

function (::_BodyMass)(; Z = nothing)
    isnothing(Z) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
    BodyMass.Z(Z)
end

# Set or generate body masses for every species in the model.

# (reassure JuliaLS)
(false) && (local BodyMass, _BodyMass)

d = NodeField(:species, :body_mass)
DT = typeof(d)
D.name_variants(::DT) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
D.type(::DT) = Float64
NF.check(::DT, input) = NF.non_negative(Float64, input)

NF.define_node_field_component(
    EN,
    d;
    #---------------------------------------------------------------------------------------
    # One extra blueprint to build from trophic levels.
    blueprints = quote
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

        function F.expand!(model, bp::Z)
            M = read(model.trophic._level) do level
                bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
            end
            $NF.expand!($d, model, M)
        end
    end,
)

# Community convenience alias.
@alias M body_mass

# Extra constructor dispatch to the extra blueprint.
function (::_BodyMass)(; Z = nothing)
    isnothing(Z) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
    BodyMass.Z(Z)
end

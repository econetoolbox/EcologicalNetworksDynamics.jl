# Set or generate body masses for every species in the model.

# (reassure JuliaLS)
(false) && (local BodyMass, _BodyMass)

nd = NodeData(:species, :body_mass)
ND = typeof(nd)
D.name_variants(::ND) = (:body_mass, :body_masses, :M)
D.type(::ND) = Float64
NF.check_value(::ND, input) = NF.non_negative(Float64, input)

NF.define_node_data_component(
    EN,
    nd;
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

        function F.expand!(model, bp::Z)
            M = read(model.trophic._level) do level
                bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
            end
            $NF.expand!($nd, model, M)
        end
    end,
)

# Community convenience alias.
@alias body_mass M

# Extra constructor dispatch to the extra blueprint.
function (::_BodyMass)(; Z = nothing)
    isnothing(Z) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
    BodyMass.Z(Z)
end

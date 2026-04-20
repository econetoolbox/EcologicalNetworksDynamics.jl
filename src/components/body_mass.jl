# Set or generate body masses for every species in the model.

# (reassure JuliaLS)
(false) && (local BodyMass, _BodyMass, BodyMass_)

let d = D.NodeField(:species, :body_mass) # Captured within bodies.
    DT = typeof(d)
    D.name_variants(::DT) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
    D.type(::DT) = Float64
    NF.check(::DT, input) = NF.non_negative(Float64, input)

    NF.define_node_field_component(
        EN,
        d;
        # One extra blueprint to build from trophic levels.
        blueprints = quote
            Foodweb = $Foodweb
            mutable struct Z <: Blueprint
                Z::Float64
            end
            @blueprint Z "trophic levels" depends(Foodweb)
            export Z
        end,
    )
    export BodyMass

    # Community convenience alias.
    @alias M body_mass

    # Extra constructor dispatch to the extra blueprint.
    function (::_BodyMass)(; M = nothing, Z = nothing)
        if isnothing(M) == isnothing(Z)
            isnothing(M) &&
                argerr("Either 'M' or 'Z' must be provided to define body masses.")
            argerr("Cannot specify both 'M' and 'Z' to define body masses.")
        end
        isnothing(Z) ? BodyMass(M) : BodyMass.Z(Z)
    end

    Z = BodyMass_.Z

    function F.early_check(bp::Z)
        (; Z) = bp
        Z >= 0 || F.checkfails("Cannot calculate body masses from trophic levels \
                                with a negative value of Z: $Z.")
    end

    function F.expand!(model, bp::Z)
        M = read(model.trophic._level) do level
            bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
        end
        NF.expand!(d, model, M)
    end
end

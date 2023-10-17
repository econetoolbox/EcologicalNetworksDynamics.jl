# Subtypes commit to specifying
# the functional response required for the simulation to run,
# and all associated required data.
# They are all mutually exclusive.
abstract type FunctionalResponse <: Component end
export FunctionalResponse

# For the sake of simplicity, to not have defaults lying everywhere.
# But this is open to discussion.
abstract type FunctionalResponseBlueprint <: Blueprint end
F.implied_blueprint_for(::FunctionalResponseBlueprint, ::Component) =
    F.cannot_imply_construct()

#-------------------------------------------------------------------------------------------
mutable struct BioenergeticResponse_ <: FunctionalResponseBlueprint
    e::Brought(Efficiency)
    y::Brought(MaximumConsumption)
    h::Brought(HillExponent)
    w::Brought(ConsumersPreferences)
    c::Brought(IntraspecificInterference)
    half_saturation_density::Brought(HalfSaturationDensity)
    BioenergeticResponse_(; kwargs...) = new(
        fields_from_kwargs(
            BioenergeticResponse_,
            kwargs;
            default = (
                e = :Miele2019,
                y = :Miele2019,
                h = 2,
                w = :homogeneous,
                c = 0,
                half_saturation_density = 0.5,
            ),
        )...,
    )
end
@blueprint BioenergeticResponse_

function F.expand!(model, ::BioenergeticResponse_)
    s = model._scratch
    ber = Internals.BioenergeticResponse(
        s[:hill_exponent],
        s[:consumers_preferences],
        s[:intraspecific_interference],
        s[:half_saturation_density],
    )
    model.functional_response = ber
end

(false) && (local BioenergeticResponse, _BioenergeticResponse) # (reassure JuliaLS)
@component begin
    BioenergeticResponse <: FunctionalResponse
    requires(
        Efficiency,
        MaximumConsumption,
        HillExponent,
        ConsumersPreferences,
        IntraspecificInterference,
        HalfSaturationDensity,
    )
    blueprints(Blueprint::BioenergeticResponse_)
end
export BioenergeticResponse

(::_BioenergeticResponse)(args...; kwargs...) = BioenergeticResponse_(args...; kwargs...)

#-------------------------------------------------------------------------------------------
mutable struct ClassicResponse_ <: FunctionalResponseBlueprint
    M::Brought(BodyMass)
    e::Brought(Efficiency)
    h::Brought(HillExponent)
    w::Brought(ConsumersPreferences)
    c::Brought(IntraspecificInterference)
    handling_time::Brought(HandlingTime)
    attack_rate::Brought(AttackRate)
    ClassicResponse_(; kwargs...) = new(
        fields_from_kwargs(
            ClassicResponse_,
            kwargs;
            default = (
                # Don't bring BodyMass by default,
                # because it has typically already been added before
                # as it is useful to calculate numerous other parameters.
                M = nothing,
                e = :Miele2019,
                h = 2,
                w = :homogeneous,
                c = 0,
                attack_rate = :Miele2019,
                handling_time = :Miele2019,
            ),
        )...,
    )
end
@blueprint ClassicResponse_

function F.expand!(model, ::ClassicResponse_)
    s = model._scratch
    clr = Internals.ClassicResponse(
        s[:hill_exponent],
        s[:consumers_preferences],
        s[:intraspecific_interference],
        s[:handling_time],
        s[:attack_rate],
    )
    model.functional_response = clr
end

(false) && (local ClassicResponse, _ClassicResponse) # (reassure JuliaLS)
@component begin
    ClassicResponse <: FunctionalResponse
    requires(
        BodyMass,
        Efficiency,
        HillExponent,
        ConsumersPreferences,
        IntraspecificInterference,
        HandlingTime,
        AttackRate,
    )
    blueprints(Blueprint::ClassicResponse_)
end
export ClassicResponse

(::_ClassicResponse)(args...; kwargs...) = ClassicResponse_(args...; kwargs...)

#-------------------------------------------------------------------------------------------
mutable struct LinearResponse_ <: FunctionalResponseBlueprint
    alpha::Brought(ConsumptionRate)
    w::Brought(ConsumersPreferences)
    LinearResponse_(; kwargs...) = new(
        fields_from_kwargs(
            LinearResponse_,
            kwargs;
            default = (alpha = 1, w = :homogeneous),
        )...,
    )
end
@blueprint LinearResponse_

function F.expand!(model, ::LinearResponse_)
    s = model._scratch
    lr = Internals.LinearResponse(s[:consumers_preferences], s[:consumption_rate])
    model.functional_response = lr
end

(false) && (local LinearResponse, _LinearResponse) # (reassure JuliaLS)
@component begin
    LinearResponse <: FunctionalResponse
    requires(ConsumptionRate, ConsumersPreferences)
    blueprints(Blueprint::LinearResponse_)
end
export LinearResponse

(::_LinearResponse)(args...; kwargs...) = LinearResponse_(args...; kwargs...)

#-------------------------------------------------------------------------------------------
# Set one, but not the others.
# TODO: this would be made easier set with an actual concept of 'Enum' components?
# (eg. all abstracts inheriting from `EnumBlueprint <: Blueprint`?)
@conflicts(BioenergeticResponse, ClassicResponse, LinearResponse)
@conflicts(BioenergeticResponse, Nti.Layer)
@conflicts(LinearResponse, Nti.Layer)

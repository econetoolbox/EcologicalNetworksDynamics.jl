module EfficiencyDef

using EcologicalNetworksDynamics: Foodweb, argerr
using EcologicalNetworksDynamics.Interface:
    EN, CS, IT, SL, Blueprint, @bp_construct, Model, @alias
using EcologicalNetworksDynamics.KwargsHelpers

const s, S = SL.EdgeField(:trophic, :efficiency)
SL.name_variants(::S) = (:efficiency, :efficiencies, :Efficiency, :Efficiencies, :e)
SL.type(::S) = Float64
IT.early_check(::S, eff::Real) = IT.fraction(Float64, eff)

#-------------------------------------------------------------------------------------------
miele2019() = (; e_herbivorous = 0.45, e_carnivorous = 0.85)

"Build from herbivorous/carnivourous rates."
mutable struct Miele2019 <: Blueprint
    e_herbivorous::Float64
    e_carnivorous::Float64
    @bp_construct Miele2019
end
IT.register_blueprint(Miele2019, "herbivorous/carnivorous efficiencies";
    s, depends = [Foodweb])

function IT.construct(::Type{Miele2019}, a...; kw...)
    @kwargs_helpers kw
    alias!(:e_herbivorous, :herb)
    alias!(:e_carnivorous, :carn)
    with_defaults!(; miele2019()...)
    no_positional(a)
    eh = take!(:e_herbivorous)
    ec = take!(:e_carnivorous)
    no_unused_arguments()
    IT.early_check.((s,), (eh, ec))
end

IT.bp_early_check(bp::Miele2019) =
    IT.early_check.((s,), (bp.e_herbivorous, bp.e_carnivorous))

# Convert to an actual matrix..
function IT.expand!(md::Model, ::Miele2019, (eh, ec))
    hA, cA = md.herbivory.matrix, md.carnivory.matrix
    e = eh * hA + ec * cA
    IT.expand!(md, s, e) # .. then rely on framework impl to lower further.
end
#-------------------------------------------------------------------------------------------

const Efficiency, _Efficiency = IT.define_web_field_component(EN, s;
    blueprints = [Miele2019])
@alias e efficiency

end

local Efficiency, _Efficiency # (reassure JuliaLS)
export Efficiency

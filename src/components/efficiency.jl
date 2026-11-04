module EfficiencyDef

using EcologicalNetworksDynamics: Foodweb
using EcologicalNetworksDynamics.NetworkFramework:
    EN, F, NF, D, Blueprint, @bp_construct, Model, @alias
using EcologicalNetworksDynamics.KwargsHelpers

const d, _D = D.EdgeField(:trophic, :efficiency)
D.name_variants(::_D) = (:efficiency, :efficiencies, :Efficiency, :Efficiencies, :e)
D.type(::_D) = Float64
D.is_sparse(::_D) = true
NF.early_check(::_D, eff::Real) = NF.fraction(Float64, eff)

miele2019() = (; e_herbivorous = 0.45, e_carnivorous = 0.85)

"Build from herbivorous/carnivourous rates."
mutable struct Miele2019 <: Blueprint
    e_herbivorous::Float64
    e_carnivorous::Float64
    @bp_construct Miele2019
end
NF.register_blueprint(Miele2019, "herbivorous/carnivorous efficiencies";
    d, depends = [Foodweb])

function NF.construct(::Type{Miele2019}; kw...)
    @kwargs_helpers kw
    with_defaults!(; miele2019()...)
    eh = take!(:e_herbivorous)
    ec = take!(:e_carnivorous)
    no_unused_arguments()
    NF.early_check.((eh, ec))
end

# TODO: the error message will confusingly report the 'efficiency' field name, will it?
NF.bp_early_check(bp::Miele2019) = NF.early_check(d, (bp.e_herbivorous, bp.e_carnivorous))

# Convert to an actual matrix..
function NF.lower(md::Model, ::Miele2019, (eh, ec))
    hA, cA = md.herbivory, md.carnivory
    e = eh * hA + ec * cA
    NF.lower(md, d, e) # .. then rely on framework impl to lower further.
end

# Codegen + exec.
const Efficiency, _Efficiency = NF.define_web_field_component(EN, d;
    blueprints = [Miele2019])
@alias e efficiency

(::_Efficiency)(default::Symbol; kw...) =
    NF.from_name(default, :Miele2019 => () -> Miele2019(; kw...); d)

end

local Efficiency, _Efficiency # (reassure JuliaLS)
export Efficiency

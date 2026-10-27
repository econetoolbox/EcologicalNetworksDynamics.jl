raw"""
The metabolic class packs species within one of 3 classes:
  - producer     (eat no other species in the model)
  - invertebrate (one particular class of consumers)
  - ectotherm    (one other particular class of consumers)

These are either manually set (then checked against a foodweb for consistency)
or automatically set in favour of invertebrate or consumers, based on a foodweb.
In any case, a foodweb component is required.
"""
module MetabolicClassDef

using EcologicalNetworksDynamics: Foodweb
using EcologicalNetworksDynamics.NetworkFramework:
    EN, D, N, F, NF, AD, Blueprint, Model, MetabolicClassDict

const d, _D = D.NodeField(:species, :metabolic_class)
D.name_variants(::_D) =
    (:metabolic_class, :metabolic_classes, :MetabolicClass, :MetabolicClasses, :class)
D.type(::_D) = Symbol

# ==========================================================================================
# Value checking.

# Inputs are checked and expanded against aliasing dict.
NF.early_check(::_D, input::Symbol) = NF.aliasing_symbol(MetabolicClassDict, input)

# When a model value is available, check against species trophic status.
function NF.late_check(md::Model, ::_D, class, ::Int, sp::Symbol)
    nw = N.network(md)
    is_producer = N.is_label(nw, sp, :producers)
    prod_class = AD.is(class, :producer, MetabolicClassDict)
    if prod_class && !is_producer
        NF.checkerr(class,
            "Metabolic class for species $(repr(sp)) \
             cannot be $(repr(class)) since it is a consumer.")
    elseif !prod_class && is_producer
        NF.checkerr(class,
            "Metabolic class for species $(repr(sp)) \
             cannot be $(repr(class)) since it is a producer.")
    end
    class
end

# ==========================================================================================
# Blueprints.

# Forbid flattening of classes because it r(b)arely makes sense.
NF.flat(::_D) = nothing

# Instead, have a blueprint *favouring* one consumer class over the other(s).
function check_favour(s)
    s = NF.convert(Symbol, s)
    NF.name_among((:all_invertebrates, :all_ectotherms), s)
end

# Construct from foodweb with a favourite consumer class.
mutable struct Favour <: Blueprint
    favourite::Symbol
    Favour(favourite) = new(check_favour(favourite))
end
NF.register_blueprint(Favour, "favourite consumer class"; d)
NF.bp_early_check(bp::Favour) = check_favour(bp.favourite)

function NF.expand!(md::Model, ::Favour, favourite)
    f = favourite == :all_invertebrates ? :invertebrate : :ectotherm
    classes = [(is_prod ? :producer : f) for is_prod in md.producers.mask]
    NF.expand!(d, md, classes)
end

# ==========================================================================================
# Component.

const MetabolicClass, _MetabolicClass = NF.define_node_field_component(
    EN, d;
    requires = [Foodweb],
    blueprints = [:Favour => Favour],
)

# Dispatch constructor to the extra blueprint.
(::_MetabolicClass)(f::Union{Symbol,AbstractString}) = Favour(f)

end
local MetabolicClass, _MetabolicClass # (reassure JuliaLS)
export MetabolicClass

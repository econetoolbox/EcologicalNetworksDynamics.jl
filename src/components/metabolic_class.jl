# The metabolic class packs species within one of 3 classes:
#   - producer     (eat no other species in the model)
#   - invertebrate (one particular class of consumers)
#   - ectotherm    (one other particular class of consumers)
#
# These are either manually set (then checked against a foodweb for consistency)
# or automatically set in favour of invertebrate or consumers, based on a foodweb.
# In any case, a foodweb component is required.

(false) && (local MetabolicClass, _MetabolicClass, MetabolicClass_) # (reassure JuliaLS)

d = NodeField(:species, :metabolic_class)
DT = typeof(d)
D.type(::DT) = Symbol
D.name_variants(::DT) =
    (:metabolic_class, :metabolic_classes, :MetabolicClass, :MetabolicClasses, :class)

# Forbid flattening of classes because it r(b)arely makes sense.
NF.flat(::DT) = nothing

# Inputs are checked against aliasing dict.
NF.check(::DT, input) = aliasing_symbol(MetabolicClassDict, input)

# If model value is available, they are checked against species trophic status.
function NF.check_with_ref(::DT, model, class, sp::Symbol)
    network = NF.network(model)
    is_producer = N.is_label(network, sp, :producers)
    prod_class = AliasingDicts.is(class, :producer, MetabolicClassDict)
    if prod_class && !is_producer
        inerr("Metabolic class for species $(repr(sp)) \
               cannot be '$class' since it is a consumer.")
    elseif !prod_class && is_producer
        inerr("Metabolic class for species $(repr(sp)) \
               cannot be '$class' since it is a producer.")
    end
    class
end


NF.define_node_field_component(
    EN,
    d;
    requires = (Foodweb,),
    #---------------------------------------------------------------------------------------
    # Construct from foodweb with a favourite consumer class.
    blueprints = quote
        Foodweb = $Foodweb
        mutable struct Favor <: Blueprint
            favourite::Symbol
        end
        @blueprint Favor "favourite consumer class" depends(Foodweb)
        export Favor
    end,
)

#-------------------------------------------------------------------------------------------
# Complete 'Favor' blueprint.

Favor = MetabolicClass.Favor

F.early_check(bp::Favor) =
    NF.name_among((:all_invertebrates, :all_ectotherms), bp.favourite)

function F.expand!(model, bp::Favor)
    f = bp.name == :all_invertebrate ? :invertebrate : :ectotherm
    classes = [is_prod ? :producer : f for is_prod in model.producers.mask]
    NF.expand!(d, model, classes)
end

# Constructors.
(::_MetabolicClass)(favourite::Symbol) = Favor(favourite)
(::_MetabolicClass)(favourite::AbstractString) = Favor(Symbol(favourite))

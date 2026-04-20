# The metabolic class packs species within one of 3 classes:
#   - producer     (eat no other species in the model)
#   - invertebrate (one particular class of consumers)
#   - ectotherm    (one other particular class of consumers)
#
# These are either manually set (then checked against a foodweb for consistency)
# or automatically set in favour of invertebrate or consumers, based on a foodweb.
# In any case, a foodweb component is required.

(false) && (local MetabolicClass, _MetabolicClass, MetabolicClass_) # (reassure JuliaLS)

d = D.NodeField(:species, :metabolic_class)
DT = typeof(d)
D.type(::DT) = Symbol
D.name_variants(::DT) =
    (:metabolic_class, :metabolic_classes, :MetabolicClass, :MetabolicClasses, :class)

# Inputs are checked and expanded against aliasing dict.
NF.check(::DT, input) = NF.aliasing_symbol(MetabolicClassDict, input)

# If model value is available, they are checked against species trophic status.
function NF.check(::DT, model::Model, class, ::Int, sp::Symbol)
    network = NF.network(model)
    is_producer = N.is_label(network, sp, :producers)
    prod_class = AliasingDicts.is(class, :producer, MetabolicClassDict)
    if prod_class && !is_producer
        inerr("Metabolic class for species $(repr(sp)) \
               cannot be $(repr(class)) since it is a consumer.")
    elseif !prod_class && is_producer
        inerr("Metabolic class for species $(repr(sp)) \
               cannot be $(repr(class)) since it is a producer.")
    end
    class
end

# Forbid flattening of classes because it r(b)arely makes sense.
NF.flat(::DT) = nothing

# Instead, have a blueprint *favouring* one consumer class over the other(s).
function check_favour(s)
    s = inputconvert(Symbol, s)
    NF.name_among((:all_invertebrates, :all_ectotherms), s)
end

NF.define_node_field_component(
    EN,
    d;
    requires = (Foodweb,),
    #---------------------------------------------------------------------------------------
    # Construct from foodweb with a favourite consumer class.
    blueprints = quote
        mutable struct Favour <: Blueprint
            favourite::Symbol
            Favour(favourite) = new($check_favour(favourite))
        end
        NF.define_blueprint(Favour, "favourite consumer class"; depends = [$Foodweb])
        export Favour
    end,
)
export MetabolicClass

#-------------------------------------------------------------------------------------------
# Complete 'Favour' blueprint.

Favour = MetabolicClass.Favour

F.early_check(bp::Favour) =
    try
        check_favour(bp.favourite)
    catch e
        e isa InputError || rethrow(e)
        F.checkfails(e.mess, rethrow)
    end

function F.expand!(model, bp::Favour)
    f = bp.favourite == :all_invertebrates ? :invertebrate : :ectotherm
    classes = [is_prod ? :producer : f for is_prod in model.producers.mask]
    NF.expand!(d, model, classes)
end

# Constructors.
(::_MetabolicClass)(favourite::Symbol) = Favour(favourite)
(::_MetabolicClass)(favourite::AbstractString) = Favour(Symbol(favourite))

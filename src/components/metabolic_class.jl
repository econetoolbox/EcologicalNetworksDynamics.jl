# The metabolic class packs species within one of 3 classes:
#   - producer     (eat no other species in the model)
#   - invertebrate (one particular class of consumers)
#   - ectotherm    (one other particular class of consumers)
#
# These are either manually set (then checked against a foodweb for consistency)
# or automatically set in favour of invertebrate or consumers, based on a foodweb.
# In any case, a foodweb component is required.

(false) && (local MetabolicClass, _MetabolicClass, MetabolicClass_) # (reassure JuliaLS)

# Checking input values.
check_metabolic_class(input) = aliasing_symbol(MetabolicClassDict, input)
check_metabolic_class(input, label, model) = check_against_status(
    check_metabolic_class(input),
    is_label(value(model), label, :producers),
    label,
    throw,
)

define_node_data_component(
    EN,
    :class,
    Symbol,
    :species,
    :Species,
    :metabolic_class,
    :MetabolicClass;
    requires = (Foodweb,),
    check_value = check_metabolic_class,
    check_against_model = check_metabolic_class,
    late_check = (;
        Raw = (_, bp, model) -> late_check(model, bp.class),
        Map = (_, bp, model) -> late_check(model, collect(values(bp.class))),
    ),
    #---------------------------------------------------------------------------------------
    # Construct from foodweb with a favourite consumer class.
    Blueprints = quote
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

function F.early_check(bp::Favor)
    (; favourite) = bp
    @check_symbol favourite (:all_invertebrates, :all_ectotherms)
end

function F.expand!(raw, bp::Favor, model)
    (; favourite) = bp
    f = @expand_symbol(
        favourite,
        :all_invertebrates => :invertebrate,
        :all_ectotherms => :ectotherm,
    )
    classes = [is_prod ? :producer : f for is_prod in model.producers.mask]
    MetabolicClass_.expand_from_vector!(raw, classes)
end

# Constructors.
(::_MetabolicClass)(favourite::Symbol) = Favor(favourite)
(::_MetabolicClass)(favourite::AbstractString) = Favor(Symbol(favourite))

#-------------------------------------------------------------------------------------------
# Late checks against foodweb.

function late_check(model, classes)
    S = model.S
    names = model.species._names
    prods = model.producers.mask
    @check_size classes S
    for (class, is_producer, name) in zip(classes, prods, names)
        check_against_status(class, is_producer, name, checkfails)
    end
end

function check_against_status(class, is_producer, name, err)
    prod_class = AliasingDicts.is(class, :producer, MetabolicClassDict)
    if prod_class && !is_producer
        err("Metabolic class for species $(repr(name)) \
             cannot be '$class' since it is a consumer.")
    elseif !prod_class && is_producer
        err("Metabolic class for species $(repr(name)) \
             cannot be '$class' since it is a producer.")
    end
    class
end

# XXX: requires(Foodweb)
# XXX: mutate with char/string rhs?

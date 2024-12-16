# The metabolic class packs species within one of 3 classes:
#   - producer     (eat no other species in the model)
#   - invertebrate (one particular class of consumers)
#   - ectotherm    (one other particular class of consumers)
#
# These are either manually set (then checked against a foodweb for consistency)
# or automatically set in favour of invertebrate or consumers, based on a foodweb.
# In any case, a foodweb component is required.

# (reassure JuliaLS)
(false) && (local MetabolicClass, _MetabolicClass, MetabolicClassDict)

# ==========================================================================================
# Blueprints.

module MetabolicClass_
include("blueprint_modules.jl")
include("./blueprint_modules_identifiers.jl")
import .EcologicalNetworksDynamics: Species, _Species, Foodweb, _Foodweb
include("./allometry_identifiers.jl")

#-------------------------------------------------------------------------------------------
# From raw values.

mutable struct Raw <: Blueprint
    classes::Vector{Symbol}
    species::Brought(Species)
    Raw(classes, sp = _Species) = new(@tographdata(classes, Vector{Symbol}), sp)
end
F.implied_blueprint_for(bp::Raw, ::_Species) = Species(length(bp.classes))
@blueprint Raw "metabolic classes" depends(Foodweb)
export Raw

F.early_check(bp::Raw) = check_nodes(check, bp.classes)
check(class, ref = nothing) =
    try
        AliasingDicts.standardize(class, MetabolicClassDict)
    catch e
        e isa AliasingError && checkrefails(e) do e
            index = if isnothing(ref)
                ""
            else
                (i,) = ref
                " $(repr(i))"
            end
            "Metabolic class input$index: $e"
        end
        rethrow(e)
    end

F.late_check(raw, bp::Raw) = late_check(raw, bp.classes)
function late_check(raw, classes)
    S = @get raw.S
    names = @ref raw.species.names
    prods = @ref raw.producers.mask

    @check_size classes S

    for (class, is_producer, sp) in zip(classes, prods, names)
        check_against_status(class, is_producer, sp)
    end
end
function check_against_status(class, is_producer, sp)
    prod_class = AliasingDicts.is(class, :producer, MetabolicClassDict)
    if prod_class && !is_producer
        checkfails("Metabolic class for species $(repr(sp)) \
                    cannot be '$class' since it is a consumer.")
    elseif !prod_class && is_producer
        checkfails("Metabolic class for species $(repr(sp)) \
                    cannot be '$class' since it is a producer.")
    end
end


function F.expand!(raw, bp::Raw)
    # Get rid of aliases and standardize classes symbols.
    classes = AliasingDicts.standardize.(bp.classes, MetabolicClassDict)
    expand!(raw, classes)
end
# Legacy conversion.
expand!(raw, classes) = raw._foodweb.metabolic_class = String.(classes)

#-------------------------------------------------------------------------------------------
# From a species-indexed map.

mutable struct Map <: Blueprint
    classes::@GraphData Map{Symbol}
    species::Brought(Species)
    Map(M, sp = _Species) = new(@tographdata(M, Map{Symbol}), sp)
end
F.implied_blueprint_for(bp::Map, ::_Species) = Species(refspace(bp.classes))
@blueprint Map "[species => class] map" depends(Foodweb)
export Map

F.early_check(bp::Map) = check_nodes(check, bp.classes)
function F.late_check(raw, bp::Map)
    (; classes) = bp
    index = @ref raw.species.index
    @check_list_refs classes :species index dense
    late_check(raw, collect(values(classes)))
end

function F.expand!(raw, bp::Map)
    index = @ref raw.species.index
    std(c) = AliasingDicts.standardize(c, MetabolicClassDict)
    c = Dict(sp => std(c) for (sp, c) in bp.classes)
    c = to_dense_vector(c, index)
    expand!(raw, c)
end

#-------------------------------------------------------------------------------------------
# From the foodweb itself, favouring either consumer class.

mutable struct Favor <: Blueprint
    favourite::Symbol
end
@blueprint Favor "favourite consumer class" depends(Foodweb)
export Favor

function F.early_check(bp::Favor)
    (; favourite) = bp
    @check_symbol favourite (:all_invertebrates, :all_ectotherms)
end

function F.expand!(raw, bp::Favor)
    (; favourite) = bp
    f = @expand_symbol(
        favourite,
        :all_invertebrates => :invertebrate,
        :all_ectotherms => :ectotherm,
    )
    classes = [is_prod ? :producer : f for is_prod in @ref raw.producers.mask]
    expand!(raw, classes)
end

end

# ==========================================================================================
# Component and generic constructors.

@component MetabolicClass{Internal} requires(Foodweb) blueprints(MetabolicClass_)
export MetabolicClass

(::_MetabolicClass)(favourite::Symbol) = MetabolicClass.Favor(favourite)
(::_MetabolicClass)(favourite::AbstractString) = MetabolicClass.Favor(Symbol(favourite))
function (::_MetabolicClass)(classes)
    c = @tographdata classes {Vector, Map}{Symbol}
    if c isa Vector
        MetabolicClass.Raw(c)
    else
        MetabolicClass.Map(c)
    end
end

# Basic query.
@expose_data nodes begin
    property(metabolic_class)
    depends(MetabolicClass)
    @species_index
    ref_cached(raw -> Symbol.(raw._foodweb.metabolic_class)) # Legacy reverse conversion.
    get(MetabolicClasses{Symbol}, "species")
    write!((raw, rhs, i) -> begin
        rhs = MetabolicClass_.check(rhs, i)
        is_prod = is_producer(raw, i)
        MetabolicClass_.check_against_status(rhs, is_prod, i)
        raw._foodweb.metabolic_class[i...] = String(rhs)
        rhs
    end)
end

# Display.
function F.shortline(io::IO, model::Model, ::_MetabolicClass)
    print(io, "Metabolic classes: [$(join_elided(model.metabolic_class, ", "))]")
end

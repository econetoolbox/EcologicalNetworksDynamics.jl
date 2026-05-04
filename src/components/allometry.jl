# Some typical blueprints expand by constructing biorates
# from body masses, metabolic classes and allometry relations.
# Here are common procedure to defining them.

include("./allometry_api.jl")
include("./allometry_identifiers.jl")
using .AllometryApi
export Allometry

"""
    boltzmann(Ea, T, T0)

Calculates the temperature dependence term of the Boltzmann-Arrhenius equation,
normalised to 20°C.
Credit: Hanna Mayal 2022-10-07 c0d3a03bec1777768e49f305d228248c4bac1a7e.
"""
function boltzmann(Ea, T; T0 = 293.15)
    k = 8.617e-5
    normalised_T = T0 - T
    denom = k * T0 * T
    exp(Ea * (normalised_T / denom))
end

# Construct vector of allometric rates based on the given data.
function allometric_rates(al::Allometry, masses, classes; E_a = 0, T = 1)
    bz = boltzmann(E_a, T)
    map(zip(masses, classes)) do (M, class)
        a, b = al[class][:a], al[class][:b]
        bz * a * M^b
    end
end

"""
Expand into biorates using allometric relations.
"""
abstract type AllometricBlueprint <: Blueprint end

"""
Expand into biorates using allometric relations,
activation energy and the model's temperature.
"""
abstract type TemperatureAllometricBlueprint <: Blueprint end

"""
Produce two blueprints within a module named after the component.
Return that module.
"""
function define_allometry_blueprints(
    mod::Module,
    d::AbstractNodeField,
    allometric_template::Allometry,
    temperature_template::@NamedTuple{E_a::Float64, allometry::Allometry},
)
    nc = NodeClass(d)
    Class = D.CamelCaseSingular(nc)
    class, field = D.content(d)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_)
    _Value = Symbol(:_, Value) # Component type name.

    Mod = Symbol(Values, :Allometry_)
    bpmod = mod.eval(
        (
            quote
                module $Mod
                using EcologicalNetworksDynamics: EN, NF, F, Model, Allometry
                const d = $d
                end
            end
        ).args |> last,
    )

    # Base allometry relations.
    bpmod.eval(
        quote
            mutable struct Allometric <: EN.AllometricBlueprint
                allometry::Allometry
                Allometric(allometry::Allometry) = new(allometry)
                Allometric(; kwargs...) = new(EN.parse_allometry_arguments(kwargs))
                Allometric(default::Symbol) =
                    new(EN.construct(d, EN.AllometricBlueprint, default))
            end
            F.define_blueprint(
                Allometric,
                "allometric rates";
                depends = [EN.BodyMass, EN.MetabolicClass],
            )
            F.early_check(bp::Allometric) = EN.early_check(d, bp, $allometric_template)
            F.expand!(m::Model, bp::Allometry, _) = EN.expand!(d, m, bp)
            export Allometric
        end,
    )

    # Temperature-dependent allometry relations.
    bpmod.eval(
        quote
            mutable struct Temperature <: EN.TemperatureAllometricBlueprint
                E_a::Float64
                allometry::Allometry
                Temperature(E_a, allometry::Allometry) = new(E_a, allometry)
                Temperature(E_a; kwargs...) =
                    new(E_a, EN.parse_allometry_arguments(kwargs))
                Temperature(default::Symbol) =
                    new(EN.construct(d, EN.TemperatureAllometricBlueprint, default))
            end
            F.define_blueprint(
                Temperature,
                "allometric rates and activation energy";
                depends = [EN.BodyMass, EN.MetabolicClass, EN.Temperature],
            )
            F.early_check(bp::Allometric) =
                EN.early_check(d, bp, $(temperature_template.allometry))
            F.expand!(m::Model, bp::Allometry, _) = EN.expand!(d, m, bp)
            export Temperature

        end,
    )

    bpmod
end

#-------------------------------------------------------------------------------------------

construct(::AbstractNodeField, ::Type{<:AllometricBlueprint}, lit::Symbol) =
    throw("unimplemented")
construct(::AbstractNodeField, ::Type{<:TemperatureAllometricBlueprint}, lit::Symbol) =
    throw("unimplemented")

#-------------------------------------------------------------------------------------------

# Check the given parameters against a template (typically a default value)
# so as to reject missing or unexpected values.
function early_check(
    d::AbstractNodeField,
    bp::Union{AllometricBlueprint,TemperatureAllometricBlueprint},
    template::Allometry,
)
    (; allometry) = bp
    (; isin, shortest, display_short) = AliasingDicts
    MC = MetabolicClassDict
    AP = AllometricParametersDict
    field = D.snake_case_plural(d)

    expected_classes = Set(k for (k, sub) in template if !isempty(sub))
    for (mc, sub) in allometry

        # Check against unexpected metabolic classes.
        if isin(mc, expected_classes, MC)
            pop!(expected_classes, mc)
        else
            isempty(sub) || F.checkfails("Allometric rates for '$mc' are meaningless \
                                          in the context of calculating $field: \
                                          $(display_short(sub)).")
        end

        expected_parms = Set(keys(template[mc]))
        for (parm, value) in sub

            # Check against unexpected parameters.
            if isin(parm, expected_parms, AP)
                pop!(expected_parms, parm)
            else
                s = shortest(parm, AP)
                F.checkfails("Allometric parameter '$s' ($parm) for '$mc' is meaningless \
                              in the context of calculating $field: $value.")
            end

        end

        # Check against missing parameters.
        if !isempty(expected_parms)
            miss = pop!(expected_parms)
            s = shortest(miss, AP)
            F.checkfails("Missing allometric parameter '$s' ($miss) for '$mc', \
                          required to calculate $field.")
        end
    end

    # Check against missing metabolic classes.
    if !isempty(expected_classes)
        miss = pop!(expected_classes)
        F.checkfails("Missing allometric rates for metabolic class '$miss', \
                      required to calculate $field.")
    end
end

#-------------------------------------------------------------------------------------------

expand!(d::AbstractNodeField, model::Model, bp::AllometricBlueprint) =
    expand!(d, model, bp.allometry)

function expand!(d::AbstractNodeField, model::Model, bp::TemperatureAllometricBlueprint)
    (; E_a, allometry) = bp
    T = model.T
    expand!(d, model, allometry; E_a, T)
end

# Expand for dense nodes.
function expand!(d::NodeField, model::Model, al::Allometry; kwargs...)
    n = N.network(model)
    c = D.class(d)
    class = N.class(n, c)
    field = D.field(d)
    data = allometric_rates(al, model.M, model.metabolic_class; kwargs...)
    N.add_field!(class, field, data)
end

# Expand for sparse nodes.
function expand!(d::SparseNodeField, model::Model, al::Allometry; kwargs...)
    n = N.network(model)
    c = D.class(d)
    class = N.class(n, c)
    field = D.field(d)
    r = N.restriction(n, c)
    inds = N.indices(r)
    M = (model.M[i] for i in inds)
    mc = (model.metabolic_class[i] for i in inds)
    data = allometric_rates(al, M, mc; kwargs...)
    N.add_field!(class, field, data)
end

#-------------------------------------------------------------------------------------------

# XXX: reuse for allometric blueprint for edges when it's time.

# Same for edges, using both source 'b' and target 'c' exponents.
function fill_edges_allometry!(mat, al::Allometry, indices, masses, classes; E_a = 0, T = 1)
    bz = boltzmann(E_a, T)
    for (i, j) in indices
        class_i, class_j = classes[i], classes[j]
        Mi, Mj = masses[i], masses[j]
        ai, bi, cj = al[class_i][:a], al[class_i][:b], al[class_j][:c]
        mat[i, j] = bz * ai * Mi^bi * Mj^cj
    end
    mat
end

function dense_edges_allometry(al::Allometry, masses, classes; kwargs...)
    S = length(masses)
    mat = zeros((S, S))
    fill_edges_allometry!(mat, al, Iterators.product(1:S, 1:S), masses, classes; kwargs...)
end

function sparse_edges_allometry(
    al::Allometry,
    only::SparseMatrix{Bool},
    masses,
    classes;
    kwargs...,
)
    S = length(masses)
    mat = spzeros((S, S))
    sources, targets, _ = findnz(only)
    fill_edges_allometry!(mat, al, zip(sources, targets), masses, classes; kwargs...)
end

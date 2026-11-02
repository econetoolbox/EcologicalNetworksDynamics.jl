# Some typical blueprints expand by constructing biorates
# from body masses, metabolic classes and allometry relations.
# Here are common procedure to defining them.

include("./allometry_api.jl")
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

"Abstract allometry blueprint."
abstract type AllometryBlueprint <: Blueprint end

"Expand into biorates using allometric relations."
abstract type AllometricBlueprint <: AllometryBlueprint end

"""
Expand into biorates using allometric relations,
activation energy and the model's temperature.
"""
abstract type TemperatureAllometricBlueprint <: AllometryBlueprint end

"""
Produce two blueprints within a module named after the component.
Return that module.
"""
function define_allometry_blueprints(
    mod::Module,
    d::D.NodeField,
    allometric_template::Allometry,
    temperature_template::@NamedTuple{E_a::Float64, allometry::Allometry},
)
    nc, _ = D.Class(d)
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
                using EcologicalNetworksDynamics.NetworkFramework:
                    EN, NF, F, Model, Allometry, @bp_construct
                const d = $d
                end
            end
        ).args |> last,
    )

    # Base allometry relations.
    bpmod.eval(
        quote
            mutable struct Allometric <: NF.AllometricBlueprint
                allometry::Allometry
                @bp_construct Allometric
            end
            export Allometric
            NF.register_blueprint(Allometric, "allometric rates"; d,
                depends = [EN.BodyMass, EN.MetabolicClass])
            NF.allometry_template(::Type{Allometric}) = $allometric_template
        end)

    # Temperature-dependent allometry relations.
    bpmod.eval(
        quote
            mutable struct Temperature <: NF.TemperatureAllometricBlueprint
                E_a::Float64
                allometry::Allometry
                @bp_construct Temperature
            end
            export Temperature
            NF.register_blueprint(Temperature,
                "allometric rates and activation energy"; d,
                depends = [EN.BodyMass, EN.MetabolicClass, EN.Temperature])
            NF.allometry_template(::Type{Temperature}) = $(last(temperature_template))
        end)

    bpmod
end

# ==========================================================================================
# Specialization.

#-------------------------------------------------------------------------------------------
# Construct.
# Typically from a value in the literature, named by a symbol.
# But leave this decision to the blueprint author.

construct(BP::Type{<:AllometricBlueprint}, al::Allometry) =
    (cst_early_check(BP, al),)
function construct(BP::Type{<:AllometricBlueprint}; kw...)
    al = Allometry(; kw...)
    (cst_early_check(BP, al),)
end

function construct(BP::Type{<:TemperatureAllometricBlueprint}, E_a, al::Allometry)
    E_a = NF.convert(Float64, E_a)
    al = cst_early_check(BP, al)
    (E_a, al)
end
function construct(BP::Type{<:TemperatureAllometricBlueprint}, E_a; kw...)
    al = Allometry(; kw...)
    construct(BP, E_a, al)
end

#-------------------------------------------------------------------------------------------
# Early check.
# Happens against a template (typically a default value)
# so as to reject missing or unexpected values.

"The allometry template associated to this data kind."
allometry_template(bp::AllometricBlueprint) = unimplemented(allometry_template, bp)

data(bp::AllometryBlueprint) = bp.allometry

function cst_early_check( BP::Type{<:AllometryBlueprint}, allometry)
    d = dispatcher(BP)
    template = allometry_template(BP)
    (; isin, shortest, display_short) = AliasingDicts
    MC = MetabolicClassDict
    AP = AllometricParametersDict
    field = D.snake_case_plural(d)
    gr(x) = "$green$x$reset"
    yl(x) = "$yellow$x$reset"
    cy(x) = "$cyan$x$reset"

    expected_classes = Set(k for (k, sub) in template if !isempty(sub))
    for (mc, sub) in allometry

        # Check against unexpected metabolic classes.
        if isin(mc, expected_classes, MC)
            pop!(expected_classes, mc)
        else
            isempty(sub) || checkerr(
                allometry,
                "Allometric rates for $(gr(mc)) are meaningless \
                 in the context of calculating $(gr(field)): \
                 $(display_short(sub)).")
        end

        expected_parms = Set(keys(template[mc]))
        for (parm, value) in sub

            # Check against unexpected parameters.
            if isin(parm, expected_parms, AP)
                pop!(expected_parms, parm)
            else
                s = shortest(parm, AP)
                checkerr(allometry,
                    "Allometric parameter $(yl(s)) ($(yl(parm))) for $(gr(mc)) \
                     is meaningless in the context \
                     of calculating $(gr(field)): $(cy(value)).")
            end

        end

        # Check against missing parameters.
        if !isempty(expected_parms)
            miss = pop!(expected_parms)
            s = shortest(miss, AP)
            checkerr(allometry,
                "Missing allometric parameter $(yl(s)) ($(yl(miss))) for $(gr(mc)), \
                 required to calculate $(gr(field)).")
        end
    end

    # Check against missing metabolic classes.
    if !isempty(expected_classes)
        miss = pop!(expected_classes)
        checkerr(allometry,
            "Missing allometric rates for metabolic class $(yl(miss)), \
             required to calculate $(gr(field)).")
    end

    allometry
end

#-------------------------------------------------------------------------------------------
# Expand.

expand!(md::Model, bp::AllometricBlueprint, al) = expand!(md, dispatcher(bp), al)
function expand!(md::Model, bp::TemperatureAllometricBlueprint, allometry)
    d = dispatcher(bp)
    (; E_a) = bp
    (; T) = md
    expand!(md, d, allometry; E_a, T)
end

function expand!(md::Model, d::D.NodeField, al::Allometry; kwargs...)
    f = D.field(d)
    M, mc = if N.is_root(md, d)
        md.M, md.metabolic_class
    else
        cl = N.class(md, d)
        rs = cl.restriction
        inds = N.indices(rs)
        # Filter out relevant values.
        M = read(md._body_mass) do M
            [M[i] for i in inds]
        end
        mc = read(md._metabolic_class) do mc
            [mc[i] for i in inds]
        end
        M, mc
    end
    data = allometric_rates(al, M, mc; kwargs...)
    N.add_field!(cl, f, data)
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

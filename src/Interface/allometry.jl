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

"Construct vector of allometric rates based on the given data."
function allometric_rates(al::Allometry, masses, classes;
    E_a = 0, T = 1)
    bz = boltzmann(E_a, T)
    map(zip(masses, classes)) do (M, class)
        a, b = al[class][:a], al[class][:b]
        bz * a * M^b
    end
end

"Construct flattened matrix based on ordered paired data for edge fields."
function paired_allometric_rates(al::Allometry, paired_masses, paired_classes;
    E_a = 0, T = 1)
    bz = boltzmann(E_a, T)
    map(zip(paired_masses, paired_classes)) do ((M_i, M_j), (class_i, class_j))
        a_i, b_i, c_j = al[class_i][:a], al[class_i][:b], al[class_j][:c]
        bz * a_i * M_i^b_i * M_j^c_j
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

const TAllometry = @NamedTuple{E_a::Float64, allometry::Allometry}
const Named{A} = Pair{Symbol,A}
"""
Produce two blueprints within a module named after the component.
Return that module.
"""
function define_allometry_blueprints(
    mod::Module,
    s::Union{SL.NodeField,SL.EdgeField};
    base::Option{Named{Allometry}} = nothing,
    temperature::Option{Named{TAllometry}} = nothing,
)
    singular, plural, Singular, Plural, short = SL.name_variants(s)
    T = SL.type(s)

    Mod = Symbol(Plural, :Allometry)
    bpmod = mod.eval(
        (
            quote
                module $Mod
                using EcologicalNetworksDynamics.Interface:
                    EN, IT, Model, Allometry, @bp_construct
                const s = $s
                end
            end
        ).args |> last,
    )

    # Base allometry relations.
    if !isnothing(base)
        default, base = base
        default = Meta.quot(default)
        bpmod.eval(
            quote
                mutable struct Allometric <: IT.AllometricBlueprint
                    allometry::Allometry
                    @bp_construct Allometric
                end
                export Allometric
                IT.register_blueprint(Allometric, "allometric rates"; s,
                    depends = [EN.BodyMass, EN.MetabolicClass])
                IT.allometry_template(::Type{Allometric}) = $base
                # Construct named default.
                IT.construct(::Type{Allometric}, lit::Symbol) =
                    (IT.from_name(lit, $default => () -> $base),)
            end)
    end

    # Temperature-dependent allometry relations.
    if !isnothing(temperature)
        default, temperature = temperature
        default = Meta.quot(default)
        bpmod.eval(
            quote
                mutable struct Temperature <: IT.TemperatureAllometricBlueprint
                    E_a::Float64
                    allometry::Allometry
                    @bp_construct Temperature
                end
                export Temperature
                IT.register_blueprint(Temperature,
                    "allometric rates and activation energy"; s,
                    depends = [EN.BodyMass, EN.MetabolicClass, EN.Temperature])
                IT.allometry_template(::Type{Temperature}) = $(last(temperature))
                IT.construct(::Type{Temperature}, lit::Symbol) =
                    IT.from_name(lit, $default => () -> $temperature)
            end)
    end

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
    E_a = IT.convert(Float64, E_a)
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

function cst_early_check(BP::Type{<:AllometryBlueprint}, allometry)
    s = selector(BP)
    template = allometry_template(BP)
    (; isin, shortest, display_short) = AliasingDicts
    MC = MetabolicClassDict
    AP = AllometricParametersDict
    field = SL.snake_case_plural(s)
    gr, yl, cy = col.((green, yellow, cyan))

    expected_classes = Set(k for (k, sub) in template if !isempty(sub))
    for (mc, sub) in allometry

        # Check against unexpected metabolic classes.
        if isin(mc, expected_classes, MC)
            isempty(sub) && continue # Cannot exactly be considered 'found' then.
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

expand!(md::Model, bp::AllometricBlueprint, al) = expand!(md, selector(bp), al)
function expand!(md::Model, bp::TemperatureAllometricBlueprint, allometry)
    s = selector(bp)
    (; E_a) = bp
    (; T) = md
    expand!(md, s, allometry; E_a, T)
end

function expand!(md::Model, s::SL.NodeField, al::Allometry; kwargs...)
    f, cl = SL.fieldname(s), ST.class(md, s)
    M, mc = if ST.is_root(md, s)
        md.M, md.species.metabolic_class
    else
        rs = cl.restriction
        inds = ST.indices(rs)
        # Filter out relevant values.
        M = read(md.species._body_mass) do M
            [M[i] for i in inds]
        end
        mc = read(md.species._metabolic_class) do mc
            [mc[i] for i in inds]
        end
        M, mc
    end
    data = allometric_rates(al, M, mc; kwargs...)
    ST.add_field!(cl, f, data)
end

function expand!(md::Model, s::SL.EdgeField, al::Allometry; kwargs...)
    f, wb = SL.fieldname(s), ST.web(md, s)
    edges = ST.edges(wb.topology)
    data = read(md.species._body_mass, md.species._metabolic_class) do M, mc
        paired_allometric_rates(al,
            ((M[i], M[j]) for (i, j) in edges),
            ((mc[i], mc[j]) for (i, j) in edges),
            ; kwargs...)
    end
    ST.add_field!(wb, f, data)
end

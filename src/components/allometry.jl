# Some typical blueprints expand by constructing biorates
# from body masses, metabolic classes and allometry relations.
# Here are common procedure to defining them.

include("./allometry_api.jl")
include("./allometry_identifiers.jl")
using .AllometryApi
export Allometry

# HERE: `define_allometry_blueprints()`

# Check the given parameters against a template (typically a default value)
# so as to reject missing or unexpected values.
function check_template(allometry::Allometry, template::Allometry, biorate)
    (; isin, shortest, display_short) = AliasingDicts
    MC = MetabolicClassDict
    AP = AllometricParametersDict

    expected_classes = Set(k for (k, sub) in template if !isempty(sub))
    for (mc, sub) in allometry

        # Check against unexpected metabolic classes.
        if isin(mc, expected_classes, MC)
            pop!(expected_classes, mc)
        else
            isempty(sub) || F.checkfails("Allometric rates for '$mc' are meaningless \
                                          in the context of calculating $biorate: \
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
                              in the context of calculating $biorate: $value.")
            end

        end

        # Check against missing parameters.
        if !isempty(expected_parms)
            miss = pop!(expected_parms)
            s = shortest(miss, AP)
            F.checkfails("Missing allometric parameter '$s' ($miss) for '$mc', \
                          required to calculate $biorate.")
        end
    end

    # Check against missing metabolic classes.
    if !isempty(expected_classes)
        miss = pop!(expected_classes)
        F.checkfails("Missing allometric rates for metabolic class '$miss', \
                      required to calculate $biorate.")
    end
end

#-------------------------------------------------------------------------------------------

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

# Fill up allometric vector for nodes, using only the 'source' exponent 'b'.
function fill_nodes_allometry!(
    vec,
    al::Allometry,
    indices,
    masses,
    classes;
    # Setup the following for temperature-dependent allometry.
    E_a = 0,
    T = 1,
)
    bz = boltzmann(E_a, T)
    for i in indices
        M = masses[i]
        class = classes[i]
        a, b = al[class][:a], al[class][:b]
        vec[i] = bz * a * M^b
    end
    vec
end

# Include all species into a dense vector.
function dense_nodes_allometry(al::Allometry, masses, classes; kwargs...)
    S = length(masses)
    res = zeros(S)
    fill_nodes_allometry!(res, al, 1:S, masses, classes; kwargs...)
end

# Only include species with the given metabolic classes.
function sparse_nodes_allometry(
    al::Allometry,
    only::SparseVector{Bool},
    masses,
    classes;
    kwargs...,
)
    S = length(masses)
    res = spzeros(S)
    sources, _ = findnz(only)
    fill_nodes_allometry!(res, al, sources, masses, classes; kwargs...)
end

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

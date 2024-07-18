# The methods defined here depends on several components,
# which is the reason they live after all components specifications.

import SciMLBase: AbstractODESolution
const Solution = AbstractODESolution

# Major purpose of the whole model specification: simulate dynamics.
# TODO: This actual system method is useful to check required components
# but is is *not* the function exposed
# because a reference to the original model needs to be forwarded down to the internals
# to save a copy next to the results,
# and the @method macro misses the feature of providing this reference yet.
function _simulate(model::InnerParms, u0, tmax::Integer; kwargs...)
    # Depart from the legacy Internal defaults.
    @kwargs_helpers kwargs

    # No default simulation time anymore.
    given(:tmax) && argerr("Received two values for 'tmax': $tmax and $(take!(:tmax)).")

    # If set, produce an @info message
    # to warn user about possible degenerated network topologies.
    deg_top_arg = :show_degenerated_biomass_graph_properties
    deg_top = take_or!(deg_top_arg, true)

    # Lower threshold.
    extinction_threshold = take_or!(:extinction_threshold, 1e-12, Any)
    extinction_threshold = @tographdata extinction_threshold {Scalar, Vector}{Float64}

    # Shoo.
    verbose = take_or!(:verbose, false)

    # No TerminateSteadyState.
    extc = extinction_callback(model, extinction_threshold; verbose)
    callback = take_or!(:callbacks, Internals.CallbackSet(extc))

    out = Internals.simulate(
        model,
        u0;
        tmax,
        extinction_threshold,
        callback,
        verbose,
        kwargs...,
    )

    deg_top &&
        show_degenerated_biomass_graph_properties(model, out[end][species_indices(out)])

    out
end
@method _simulate depends(FunctionalResponse, ProducerGrowth, Metabolism, Mortality)

# This exposed method does forward reference down to the internals..
simulate(model::Model, u0, tmax::Integer; kwargs...) =
    _simulate(model, u0, tmax; model, kwargs...)
# .. so that we *can* retrieve the original model from the simulation result.
get_model(sol::Solution) = copy(sol.prob.p.model) # (owned copy to not leak aliases)
export simulate, get_model

"""
    species_indices(sol::Solution)

Retrieve the correct indices to extract species-related data from simulation output.
"""
function species_indices(sol::Solution)
    m = get_model(sol)
    1:(m.n_species)
end

"""
    nutrients_indices(sol::Solution)

Retrieve the correct indices to extract nutrients-related data from simulation output.
"""
function nutrients_indices(sol::Solution)
    m = get_model(sol)
    N = m.n_nutrients
    S = m.n_species
    (S+1):(S+N)
end

# Re-expose from internals so it works with the new API.
extinction_callback(m, thr; verbose = false) = Internals.ExtinctionCallback(thr, m, verbose)
export extinction_callback
@method extinction_callback depends(
    FunctionalResponse,
    ProducerGrowth,
    Metabolism,
    Mortality,
)

# Collect topology diagnostics after simulation and decide whether to display them or not.
function show_degenerated_biomass_graph_properties(model, biomass)
    g = model.topology
    restrict_to_live_species!(g, biomass)
    diagnostics = []
    # Consume iterator to return lengths without collecting allocated yielded values.
    function count(it)
        res = 0
        for _ in it
            res += 1
        end
        res
    end
    for comp in disconnected_components(g)
        sp = live_species(g)
        prods = live_producers(model, g)
        cons = live_consumers(model, g)
        ip = isolated_producers(model, comp)
        sc = starving_consumers(model, comp)
        push!(diagnostics, count.((sp, prods, cons, ip, sc)))
    end
    # Don't display if there is only 1 component with no degenerated nodes.
    nc = length(diagnostics)
    display = if nc > 1
        true
    else
        (_, _, _, n_ip, n_sc) = diagnostics[1]
        n_ip > 0 || n_sc > 0
    end
    if display
        s(n) = n > 1 ? "s" : ""
        println("INFO: The biomass graph at the end of simulation \
                 contains $nc disconnected component$(s(nc)):")
        for (n_sp, n_prods, n_cons, n_ip, n_sc) in enumerate(diagnostics)
            wip = if n_ip > 0
                " /!\\ including $n_ip isolated producer$(s(n_ip))"
            else
                ""
            end
            wsc = if n_sc > 0
                " /!\\ including $n_sc starving consumer$(s(n_sc))"
            else
                ""
            end
            println("  - Connected component ($n_sp species):")
            println("    - $n_prods producer$(s(n_prods))$wip")
            println("    - $n_cons producer$(s(n_cons))$wsc")
        end
        println("This message is meant to attract your attention \
                 regarding the meaning of downstream analyses \
                 depending on the simulated biomasses values.\n\
                 You can silent it with `show_unusual_biomass_graph_properties=false`.")
    end
end

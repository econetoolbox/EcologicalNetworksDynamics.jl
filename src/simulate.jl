# Major purpose of the whole model specification: simulate dynamics.

import SciMLBase: AbstractODESolution
const Solution = AbstractODESolution

# TODO: This actual system method is useful to check required components
# but is is *not* the function exposed
# because a reference to the original model needs to be forwarded down to the internals
# to save a copy next to the results,
# and the @method macro misses the feature of providing this reference yet.
function _simulate(model::InnerParms, u0, tmax::Number; kwargs...)
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
    verbose = take_or!(:show_extinction_events, false)

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
        left()...,
    )

    deg_top && show_degenerated_biomass_graph_properties(
        model,
        out.u[end][species_indices(out)],
        deg_top_arg,
    )

    out
end
@method _simulate depends(FunctionalResponse, ProducerGrowth, Metabolism, Mortality)

"""
    simulate(model::Model, u0, tmax::Number; kwargs...)

The major feature of the ecological model:
transform the model value into a set of ODEs
and attempt to resolve them numerically
to construct simulated biomasses trajectories.

  - `u0`: Initial biomass(es).
  - `tmax`: Maximum simulation time.
  - `t0 = 0`: Starting simulation date.
  - `extinction_threshold = 1e-5`: Biomass(es) values for which species are considered extinct.
  - `show_extinction_events = false`: Raise to display events during simulation.
  - `...`: additional arguments are passed to `DifferentialEquations.solve`.

Simulation results in a `Solution` object
produced by the underlying `DifferentialEquations` package.
This object contains an inner copy of the simulated model,
which may then be retrieved with `get_model()`.
"""
simulate(model::Model, u0, tmax::Number; kwargs...) =
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
export species_indices

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
export nutrients_indices

"""
    get_extinctions(sol::Solution)

Extract list of extinct species indices and their extinction dates
from the solution returned by `simulate()`.
"""
get_extinctions(sol::Solution) = deepcopy(Internals.get_extinct_species(sol))
export get_extinctions

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
function show_degenerated_biomass_graph_properties(model::InnerParms, biomass, arg)
    g = deepcopy(model.topology)
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
        sp = live_species(comp)
        prods = live_producers(model, comp)
        cons = live_consumers(model, comp)
        ip = isolated_producers(model, comp)
        sc = starving_consumers(model, comp)
        push!(diagnostics, collect.((sp, prods, cons, ip, sc)))
    end
    # Don't display if there is only 1 component with no degenerated nodes.
    nc = length(diagnostics)
    display = if nc > 1
        true
    else
        (_, _, _, ip, sc) = diagnostics[1]
        length(sc) > 0 || length(ip) > 0
    end
    if display
        s(n) = n > 1 ? "s" : ""
        m = "The biomass graph at the end of simulation"
        if nc > 1
            m *= " contains $nc disconnected components:\n"
        else
            m *= " contains degenerated species nodes:\n"
        end
        vec(i_species) = "[$(join_elided(model.species_label.(sort(i_species)), ", "))]"
        for (sp, prods, cons, ip, sc) in diagnostics
            n_sp, n_prods, n_cons, n_ip, n_sc = length.((sp, prods, cons, ip, sc))
            m *= "Connected component with $n_sp species:\n"
            if n_prods > 0
                m *= "  - "
                if n_ip == n_prods
                    m *= "/!\\ $n_ip isolated producer$(s(n_ip)) $(vec(ip))"
                else
                    m *= "$n_prods producer$(s(n_prods)) $(vec(prods))"
                    if n_ip > 0
                        m *= " /!\\ including $n_ip isolated producer$(s(n_ip)) $(vec(ip))"
                    end
                end
                m *= '\n'
            end
            if n_cons > 0
                m *= "  - "
                if n_sc == n_cons
                    m *= "/!\\ $n_sc starving consumer$(s(n_sc)) $(vec(sc))"
                else
                    m *= "$n_cons consumer$(s(n_cons)) $(vec(cons))"
                    if n_sc > 0
                        m *= " /!\\ including $n_sc starving consumer$(s(n_sc)) $(vec(sc))"
                    end
                end
                m *= '\n'
            end
        end
        m *= "This message is meant to attract your attention \
              regarding the meaning of downstream analyses \
              depending on the simulated biomasses values.\n\
              You can silent it with `$arg=false`."
        @info m
    end
end

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

    # Lower threshold.
    extinction_threshold = take_or!(:extinction_threshold, 1e-12, Any)
    extinction_threshold = @tographdata extinction_threshold {Scalar, Vector}{Float64}

    # Shoo.
    verbose = take_or!(:verbose, false)

    # No TerminateSteadyState.
    extc = extinction_callback(model, extinction_threshold; verbose)
    callback = take_or!(:callbacks, Internals.CallbackSet(extc))

    Internals.simulate(model, u0; tmax, extinction_threshold, callback, verbose, kwargs...)
end
@method _simulate depends(FunctionalResponse, ProducerGrowth, Metabolism, Mortality)

# This exposed method does forward reference down to the internals..
simulate(model::Model, args...; kwargs...) = _simulate(model, args...; model, kwargs...)
# .. so that we *can* retrieve the original model from the simulation result.
get_model(sol::Solution) = copy(sol.prob.p.model) # (owned copy to not leak aliases)
export simulate, get_model


# Re-expose from internals so it works with the new API.
extinction_callback(m, thr; verbose = false) = Internals.ExtinctionCallback(thr, m, verbose)
export extinction_callback
@method extinction_callback depends(
    FunctionalResponse,
    ProducerGrowth,
    Metabolism,
    Mortality,
)

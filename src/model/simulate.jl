#=
Simulations of biomass dynamics
=#

"""
    simulate(
        params,
        B0;
        start=0,
        stop=500,
        use=:nonstiff,
        extinction_threshold=1e-6,
        δt=0.25
    )

Run biomass dynamics simulation,
given model parameters (`params`) and the initial biomass (`B0`).

The dynamic is solved between t=`start` and t=`stop`.
Biomass trajectories are saved every `δt`.

The output of this function is the result of `DifferentialEquations.solve()`,
to learn how to handle this output
see [Solution Handling](https://diffeq.sciml.ai/stable/basics/solution/).

# Examples
```jldoctest
julia> foodweb = FoodWeb([0 0; 1 0]); # create foodweb

julia> params = ModelParameters(foodweb); # generate its parameters

julia> B0 = [0.5, 0.5]; # set initial biomass

julia> solution = simulate(params, B0); # run simulation

julia> solution.t == collect(0:0.25:500) # saved timesteps
true

julia> solution[begin] # initial biomass, recover B0
2-element Vector{Float64}:
 0.5
 0.5

julia> round.(solution[end], digits=2) # final biomass
2-element Vector{Float64}:
 0.19
 0.22
```
"""
function simulate(
    params::ModelParameters,
    B0::AbstractVector;
    start::Number=0,
    stop::Number=500,
    alg_hints::Symbol=:auto,
    extinction_threshold::AbstractFloat=1e-6,
    δt::Number=0.25
)

    # Check for consistency and format input arguments
    S = richness(params.network)
    length(B0) ∈ [1, S] || throw(ArgumentError("B0 of size $(length(B0)) instead of $S:
        B0 should be of length 1 or S (species richness)."))
    length(B0) == S || (B0 = repeat(B0, S))
    start < stop || throw(ArgumentError("'start' ($start) should be smaller than
        'stop' ($stop)."))

    # Define callback - extinction threshold
    function species_under_threshold(u, t, integrator)
        any(0.0 .< u .< extinction_threshold)
    end
    function extinct_species!(integrator)
        integrator.u[integrator.u.<=extinction_threshold] .= 0.0
        extinct_sp = (1:length(integrator.u))[integrator.u.<=extinction_threshold]
        t = round(integrator.t, digits=2)
        println("$extinct_sp have gone extinct at time $t.")
    end
    extinction_callback = DiscreteCallback(species_under_threshold, extinct_species!)

    # Define callback - positive domain
    positive_domain = PositiveDomain()

    # Define callback - terminate at steady state
    terminate_steady_state = TerminateSteadyState(1e-6, 1e-4)

    callbacks = CallbackSet(extinction_callback, positive_domain, terminate_steady_state)

    # Define ODE problem and solve
    timespan = (float(start), float(stop))
    timesteps = collect(start:δt:stop)
    problem = ODEProblem(dBdt!, B0, timespan, params)
    solve(problem, saveat=timesteps, alg_hints=[alg_hints], callback=callbacks)
end

function find_steady_state(
    params::ModelParameters,
    B0::AbstractVector;
)

    # Check for consistency and format input arguments
    S = richness(params.network)
    length(B0) ∈ [1, S] || throw(ArgumentError("B0 of size $(length(B0)) instead of $S:
        B0 should be of length 1 or S (species richness)."))
    length(B0) == S || (B0 = repeat(B0, S))

    # Define ODE problem and solve
    problem = SteadyStateProblem(dBdt!, B0, params)
    solve(problem, SSRootfind())
end

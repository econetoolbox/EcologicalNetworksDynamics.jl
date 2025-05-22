#### Run biomass simulations ####
"""
    simulate(
        params::ModelParameters,
        B0::AbstractVector;
        alg = nothing,
        t0::Number = 0,
        tmax::Number = 500,
        dt::Float64=0.25,
        extinction_threshold::Union{Number,AbstractVector} = 1e-5,
        verbose = true,
        callback = CallbackSet(
            TerminateSteadyState(1e-6, 1e-4),
            ExtinctionCallback(extinction_threshold, verbose),
        ),
        diff_code_data = (dBdt!, params),
        kwargs...,
    )

Run biomass dynamics simulation,
given model parameters (`params`) and the initial biomass (`B0`).
You can choose your solver algorithm by specifying to the `alg` keyword.

The dynamic is solved between t=`t0` and t=`tmax`.

By default, we give the following callbacks to `solve()`:

  - `TerminateSteadyState` (from DiffEqCallbacks) which ends the simulation
    when a steady state is reached

  - `ExtinctionCallback` which extinguishes species whose biomass goes under the
    `extinction_threshold`
    (either a number or a vector, see [`ExtinctionCallback`](@ref)).

You are free to provide other callbacks, either by changing the parameter values of the
callbacks above, choosing other callbacks from DiffEqCallbacks or by creating you own
callbacks.

Moreover, we use the `isoutofdomain` argument of `solve()`
to reject time steps that lead to negative biomass values due to numerical error.

Extra performance may be achieved
by providing specialized julia code to the `diff_code_data` argument
instead of the default, generic `BEFWM2.dBdt!` code.
No need to write it yourself as [`generate_dbdt`](@ref) does it for you.

Thanks to the extra keywords arguments `kwargs...`,
you have a direct access to the interface of solve.
Thus you can directly specify keyword arguments of solve(),
for instance if you want to hint toward stiff solver
you can give as an argument to simulate `alg_hints=[:stiff]`.

The output of this function is the result of `DifferentialEquations.solve()`,
to learn how to handle this output
see [Solution Handling](https://diffeq.sciml.ai/stable/basics/solution/).

If you are not interested in the biomass trajectories,
but want to find directly the biomass at steady state see [`find_steady_state`](@ref).

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 0; 1 0]); # create the foodweb

julia> br = BioRates(foodweb; d = 0); # set natural death rate to 0

julia> params = ModelParameters(foodweb; biorates = br);

julia> B0 = [0.5, 0.5]; # set initial biomass

julia> solution = simulate(params, B0); # run simulation

julia> solution.retcode == :Terminated # => a steady state has been found
true

julia> solution[begin] == B0 # initial biomass equals initial biomass
true

julia> isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass
true

julia> using DifferentialEquations;

julia> solution_custom_alg = simulate(params, B0; alg = BS5());

julia> isapprox(solution_custom_alg[end], [0.188, 0.219]; atol = 1e-2)
true

julia> import Logging; # TODO: remove when warnings removed from `generate_dbdt`.

julia> # generate specialized code (same simulation)

julia> xpr, data = Logging.with_logger(Logging.NullLogger()) do
           generate_dbdt(params, :raw)
       end;

julia> solution = simulate(params, B0; diff_code_data = (eval(xpr), data));

julia> solution.retcode == :Terminated #  the same result is obtained, more efficiently.
true

julia> solution[begin] == B0
true

julia> isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass
true

julia> # Same with alternate style.

julia> xpr, data = Logging.with_logger(Logging.NullLogger()) do
           generate_dbdt(params, :compact)
       end;

julia> solution = simulate(params, B0; diff_code_data = (eval(xpr), data));

julia> solution.retcode == :Terminated
true

julia> solution[begin] == B0
true

julia> isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass
true
```

By default, the extinction callback throw a message when a species goes extinct.

```julia
julia> foodweb = FoodWeb([0 0; 1 0]);

julia> params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0));

julia> simulate(params, [0.5, 1e-12]; verbose = true); # default: a message is thrown
[ Info: Species [2] is exinct. t=0.12316364776188903

julia> simulate(params, [0.5, 1e-12]; verbose = false); # no message thrown

```
"""
function simulate(
    params::ModelParameters,
    B0::AbstractVector;
    alg = nothing,
    t0::Number = 0,
    tmax::Number = 500,
    dt::Float64 = 1.0,
    extinction_threshold::Union{Number,AbstractVector} = 1e-5,
    corrmat::Union{Matrix{Float64},Nothing} = nothing,
    verbose = false,
    callback = CallbackSet(
        TerminateSteadyState(1e-6, 1e-4),
        ExtinctionCallback(extinction_threshold, verbose),
    ),
    stochastic_callbacks = ExtinctionCallback(extinction_threshold, verbose, richness(params.network)),
    diff_code_data = (dBdt!, params),
    kwargs...,
)

    # Check for consistency and format input arguments
    S = richness(params.network)
    all(B0 .>= 0) || throw(
        ArgumentError(
            "Inital biomasses provided in 'B0' should be all non-negative." *
            "You gave B0 = $B0 which contains negative value(s).",
        ),
    )
    length(B0) == 1 && (B0 = repeat(B0, S))
    @check_equal_richness length(B0) S
    @check_lower_than t0 tmax
    if isa(extinction_threshold, AbstractVector)
        length(extinction_threshold) == S || throw(
            ArgumentError(
                "Length of 'extinction_threshold' vector should be equal to S (richness).",
            ),
        )
    end

    # Define ODE problem and solve
    timespan = (t0, tmax)
    extinct_sp = Dict(i => 0.0 for (i, b) in enumerate(B0) if b == 0.0)
    code, data = diff_code_data
    p = (params = data, extinct_sp = extinct_sp)
    # Work around julia's world count:
    # `generate_dbdt` only produces anonymous code,
    # so the generated functions cannot be overriden.
    # As such, and in principle, the 'latest' function is unambiguous.
    if !isa(code, Function)
        message = "The given specialized code is not a `Function` but `$(typeof(code))`."
        if isa(code, Expr)
            message *= " Did you forget to `eval()`uate it before passing it to `simulate()`?"
        end
        throw(ArgumentError(message))
    end
    fun = (args...) -> Base.invokelatest(code, args...)

    if !params.stochasticity.addstochasticity
        problem = ODEProblem(fun, B0, timespan, p)
        solve(
            problem,
            alg;
            callback = callback,
            isoutofdomain = (u, p, t) -> any(x -> x < 0, u),
            dt = dt,
            kwargs...,
        )
    else
        if !(code === dBdt!)
            throw(ArgumentError("Boost option does not work with stochasticity yet."))
        end
        problem = ODEProblem(fun, B0, timespan, p)

        diffparams = vcat(B0, params.stochasticity.μ)

        FW = params.network
        AS = params.stochasticity

        # Set up the noise process
        Γ = cov_matrix(FW, AS, corrmat)
        W = CorrelatedWienerProcess(Γ, 0.0, zeros(size(Γ, 1)))

        # Perform the actual integration
        prob = SDEProblem(
            stoch_dBdt!,
            noise_equations,
            diffparams,
            timespan,
            p;
            noise = W,
            callback = stochastic_callbacks,
        ) # Can add a seed to use same noise

        solve(prob; adaptive = false, dt = dt, callback = callback, kwargs...) # Do I need to tidy output??
    end
end
#### end ####

#### Species extinction callback ####
"""
    ExtinctionCallback(extinction_threshold::AbstractVector, verbose::Bool)

Generate a DiffEqCallbacks.DiscreteCallback to extinguish species
below the `extinction_threshold`.
The `extinction_threshold` can be either:
a `Number` (same threshold for every species)
or an `AbstractVector` of length species richness (one threshold per species).
If `verbose = true` a message is printed when a species goes extinct,
otherwise no message are printed.
"""
function ExtinctionCallback(extinction_threshold, verbose::Bool)

    # The callback is triggered whenever
    # a non-extinct species biomass goes below the threshold.

    # Use either adequate code based on `extinction_threshold` type.
    # This avoids that the type condition be checked on every timestep.
    species_under_threshold = if isa(extinction_threshold, Number)
        (u, t, integrator) -> any(u[u.>0] .< extinction_threshold)
    else
        (u, t, integrator) -> any(u[u.>0] .< extinction_threshold[u.>0])
    end

    get_extinct_species = if isa(extinction_threshold, Number)
        (u, _) -> Set(findall(x -> x < extinction_threshold, u))
    else
        (u, S) -> Set((1:S)[u.<extinction_threshold])
    end

    # Effect of the callback: the species biomass below the threshold are set to 0.
    function extinguish_species!(integrator)
        # All species that are extinct, include previous extinct species and the new species
        # that triggered the callback. (Its/Their biomass still has to be set to 0.0)
        S = length(integrator.u)
        all_extinct_sp = get_extinct_species(integrator.u, S)
        prev_extinct_sp = keys(integrator.p.extinct_sp)
        # Species that are newly extinct, i.e. the species that triggered the callback.
        new_extinct_sp = setdiff(all_extinct_sp, prev_extinct_sp)
        integrator.u[[sp for sp in new_extinct_sp]] .= 0.0
        t = integrator.t
        new_extinct_sp_dict = Dict(sp => t for sp in new_extinct_sp)
        merge!(integrator.p.extinct_sp, new_extinct_sp_dict) # update extinct species list
        # Info message (printed only if verbose = true).
        if verbose
            S, S_ext = length(integrator.u), length(all_extinct_sp)
            @info "Species $([new_extinct_sp...]) went extinct at time t = $t. \n" *
                  "$S_ext out of $S species are extinct."
        end
    end

    DiscreteCallback(species_under_threshold, extinguish_species!)
end


"""
    ExtinctionCallback(extinction_threshold::AbstractVector, verbose::Bool)

Differs from the original ExtinctionCallback as this is for stochastic simulations 
where only the first S equations are biomass timeseries subject to extinction
"""
function ExtinctionCallback(extinction_threshold, verbose::Bool, S::Number)

    # The callback is triggered whenever
    # a non-extinct species biomass goes below the threshold.

    # Use either adequate code based on `extinction_threshold` type.
    # This avoids that the type condition be checked on every timestep.
    species_under_threshold = if isa(extinction_threshold, Number)
        (u, t, integrator) -> any(u[1:S][u[1:S].!=0] .< extinction_threshold)
    else
        (u, t, integrator) -> any(u[1:S][u[1:S].!=0] .< extinction_threshold[u[1:S].>0])
    end

    get_extinct_species = if isa(extinction_threshold, Number)
        (u, _) -> Set(findall(x -> x < extinction_threshold, u[1:S]))
    else
        (u, S) -> Set((1:S)[u[1:S].<extinction_threshold])
    end

    # Effect of the callback: the species biomass below the threshold are set to 0.
    function extinguish_species!(integrator)
        # All species that are extinct, include previous extinct species and the new species
        # that triggered the callback. (Its/Their biomass still has to be set to 0.0)
        
        all_extinct_sp = get_extinct_species(integrator.u, S)
        prev_extinct_sp = keys(integrator.p.extinct_sp)
        # Species that are newly extinct, i.e. the species that triggered the callback.
        new_extinct_sp = setdiff(all_extinct_sp, prev_extinct_sp)
        integrator.u[[sp for sp in new_extinct_sp]] .= 0.0
        t = integrator.t
        new_extinct_sp_dict = Dict(sp => t for sp in new_extinct_sp)
        merge!(integrator.p.extinct_sp, new_extinct_sp_dict) # update extinct species list
        # Info message (printed only if verbose = true).
        if verbose
            S_ext = length(all_extinct_sp)
            @info "Species $([new_extinct_sp...]) went extinct at time t = $t. \n" *
                  "$S_ext out of $S species are extinct."
        end
    end

    DiscreteCallback(species_under_threshold, extinguish_species!)
end
#### end ####


#### Find steady state ####
"""
    find_steady_state(params::ModelParameters, B0::AbstractVector; kwargs...)

Find a steady state of a system parametrized by a parameter set `params`
and some initial conditions `B0`.
The function returns a tuple (`steady_state`, `terminated`).
If no steady state has been found `terminated` is set to `false`
and `steady_state` to `nothing`.
Otherwise, `terminated` is set to `true`
and `steady_state` to the corresponding value.

If you are not only interested in the steady state biomass,
but also in the trajectories see [`simulate`](@ref).

# Examples

```jldoctest
julia> foodweb = FoodWeb([0 0; 1 0]); # create the foodweb

julia> biorates = BioRates(foodweb; d = 0); # set natural death to 0

julia> params = ModelParameters(foodweb; biorates = biorates);

julia> B0 = [0.5, 0.5]; # set initial biomass

julia> solution = find_steady_state(params, B0);

julia> solution.terminated # => a steady state has been found
true

julia> round.(solution.steady_state, digits = 2) # steady state biomass
2-element Vector{Float64}:
 0.19
 0.22
```
"""
function find_steady_state(params::ModelParameters, B0::AbstractVector; kwargs...)
    solution = simulate(params, B0; kwargs...)
    terminated = has_terminated(solution)
    steady_state = terminated ? solution.u[end] : nothing
    (steady_state = steady_state, terminated = terminated)
end

has_terminated(solution) = solution.retcode == :Terminated
#### end ####

"""
    tidy_output!(output)

Takes the output of `simulate` (output.u) and splits the timeseries into:
output.t for timesteps
output.B for biomass timeseries
output.P for stochastic parameter timeseries - returns empty if deterministic simulation

Also removes duplicated timesteps generated by callbacks for extinction events.
"""
function tidy_output(params::ModelParameters, output)

    foodweb = params.network

    output = (t = output.t, B = hcat(output.u...)')

    to_drop = findall(x -> x == 0, diff(output.t)) # where diff == 0 (difference to next timestep), the callback has kicked in
    # because the length of diff(time) is length(time) - 1, to drop gives the indexes of the first of the repeated timesteps

    to_keep = setdiff([1:1:length(output.t);], to_drop) # we want everything else

    biomasses = output.B[to_keep, :]

    output = (
        t = output.t[to_keep],
        B = biomasses[:, 1:richness(foodweb)],
        P = biomasses[:, richness(foodweb)+1:size(biomasses, 2)],
    )

    return output

end

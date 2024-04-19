#### Run biomass simulations ####
"""
    simulate(
        params::ModelParameters,
        B0::AbstractVector;
        N0::AbstractVector = nothing,
        alg = nothing,
        t0::Number = 0,
        tmax::Number = 500,
        extinction_threshold::Union{Number,AbstractVector} = 1e-5,
        verbose = true,
        callback = CallbackSet(
            TerminateSteadyState(1e-6, 1e-4),
            ExtinctionCallback(extinction_threshold, length(B0), verbose),
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
instead of the default, generic `EcologicalNetworksDynamics.dBdt!` code.
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
       br = BioRates(foodweb; d = 0); # set natural death rate to 0
       params = ModelParameters(foodweb; biorates = br);
       B0 = [0.5, 0.5]; # set initial biomass
       solution = simulate(params, B0); # run simulation
       @assert is_terminated(solution) # => a steady state has been found
       @assert solution[begin] == B0 # initial biomass equals initial biomass
       @assert isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass

julia> using DifferentialEquations;
       solution_custom_alg = simulate(params, B0; alg = BS5());
       @assert isapprox(solution_custom_alg[end], [0.188, 0.219]; atol = 1e-2)

julia> import Logging; # TODO: remove when warnings removed from `generate_dbdt`.
       # generate specialized code (same simulation)
       xpr, data = Logging.with_logger(Logging.NullLogger()) do
           generate_dbdt(params, :raw)
       end;
       solution = simulate(params, B0; diff_code_data = (eval(xpr), data));
       @assert is_terminated(solution) #  the same result is obtained, more efficiently.
       @assert solution[begin] == B0
       @assert isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass

julia> # Same with alternate style.
       xpr, data = Logging.with_logger(Logging.NullLogger()) do
           generate_dbdt(params, :compact)
       end;
       solution = simulate(params, B0; diff_code_data = (eval(xpr), data));
       @assert is_terminated(solution)
       @assert solution[begin] == B0
       @assert isapprox(solution[end], [0.188, 0.219]; atol = 1e-2) # steady state biomass

```

By default, the extinction callback throw a message when a species goes extinct.

```julia
julia> foodweb = FoodWeb([0 0; 1 0]);
       params = ModelParameters(foodweb; biorates = BioRates(foodweb; d = 0));
       simulate(params, [0.5, 1e-12]; verbose = true); # default: a message is thrown
[ Info: Species [2] is exinct. t=0.12316364776188903

julia> simulate(params, [0.5, 1e-12]; verbose = true); # no message thrown

```
"""
function simulate(
    params::ModelParameters,
    B0;
    N0 = nothing,
    alg = nothing,
    t0::Number = 0,
    tmax::Number = 500,
    extinction_threshold::Union{Number,AbstractVector} = 1e-5,
    verbose = true,
    callback = CallbackSet(
        TerminateSteadyState(1e-6, 1e-4),
        ExtinctionCallback(extinction_threshold, params, verbose),
    ),
    diff_code_data = (dudt!, params),
    # FROM THE FUTURE - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # Record original user component-based model within the solution.
    # The design should change during refactoring of the internals.
    model = nothing,
    kwargs...,
)
    isnothing(model) ||
        model._value === params ||
        throw("Inconsistent input to `simulate`: this is a bug in the package.")

    # Interpret parameters and check them for consistency.
    S = richness(params)
    all(B0 .>= 0) ||
        throw(ArgumentError("The argument received B0 = $B0 contains negative value(s). \
                             Initial biomasses should all be non-negative."))
    length(B0) == 1 && (B0 = fill(B0[1], S))
    @check_equal_richness length(B0) S
    if !isnothing(N0)
        all(N0 .>= 0) || throw(
            ArgumentError("The argument received N0 = $N0 contains negative value(s). \
                           Initial nutrient abundances should all be non-negative."),
        )
    end
    @check_lower_than t0 tmax
    if isa(extinction_threshold, AbstractVector)
        length(extinction_threshold) == S || throw(
            ArgumentError(
                "Length of 'extinction_threshold' vector should be equal to S (richness).",
            ),
        )
    end

    # Handle boosted simulations.
    timespan = (t0, tmax)
    code, data = diff_code_data
    # Work around julia's world count:
    # `generate_dbdt` only produces anonymous code,
    # so the generated functions cannot be overriden.
    # As such, and in principle, the 'latest' function is unambiguous.
    if !isa(code, Function)
        message = "The given specialized code is not a `Function` but `$(typeof(code))`."
        if isa(code, Expr) || isa(code, GeneratedExpression)
            message *= " Did you forget to `eval()`uate it before passing it to `simulate()`?"
        end
        throw(ArgumentError(message))
    end
    fun = (args...) -> Base.invokelatest(code, args...)
    extinct_sp = Dict(i => 0.0 for (i, b) in enumerate(B0) if b == 0.0)

    # Set initial nutrient abundances `N0` and initial species biomass `B0`.
    if isa(params.producer_growth, NutrientIntake)
        isnothing(N0) && throw(
            ArgumentError("If producer growth is of type `$NutrientIntake`, \
                           use the `N0` argument to provide initial nutrient abundances."),
        )
        n = nutrient_richness(params)
        length(N0) == 1 && (N0 = fill(N0[1], n))
        @assert length(N0) == n || throw(
            ArgumentError("The model contains $n nutrients, \
                          but $(length(N0)) initial nutrient abundances were provided."),
        )
        u0 = vcat(B0, N0)
    else
        u0 = B0
    end

    p = (
        params = data,
        extinct_sp = extinct_sp,
        original_params = params,
        # Own the copy to not allow post-simulation modifications.
        model = isnothing(model) ? nothing : copy(model),
    )
    timespan = (t0, tmax)
    problem = ODEProblem(fun, u0, timespan, p)
    sol = solve(
        problem,
        alg;
        callback = callback,
        isoutofdomain = (u, p, t) -> any(x -> x < 0, u),
        kwargs...,
    )
    sol
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
function ExtinctionCallback(extinction_threshold, p::ModelParameters, verbose::Bool)
    # The callback is triggered whenever
    # a non-extinct species biomass goes below the threshold.
    # Use either adequate code based on `extinction_threshold` type.
    # This avoids that the type condition be checked on every timestep.
    sp = species_indices(p) # Vector of species indexes.
    species_under_threshold = if isa(extinction_threshold, Number)
        (u, _, _) -> any(u[sp][u[sp].>0] .< extinction_threshold)
    else
        (u, _, _) -> any(u[sp][u[sp].>0] .< extinction_threshold[u[sp].>0])
    end

    get_extinct_species = if isa(extinction_threshold, Number)
        (u, sp) -> Set(findall(x -> x < extinction_threshold, u[sp]))
    else
        (u, sp) -> Set(sp[u[sp].<extinction_threshold])
    end

    # Effect of the callback: the species biomass below the threshold are set to 0.
    function extinguish_species!(integrator)
        # All species that are extinct, include previous extinct species and the new species
        # that triggered the callback. (Its/Their biomass still has to be set to 0.0)
        all_extinct_sp = get_extinct_species(integrator.u, sp)
        prev_extinct_sp = keys(integrator.p.extinct_sp)
        # Species that are newly extinct, i.e. the species that triggered the callback.
        new_extinct_sp = setdiff(all_extinct_sp, prev_extinct_sp)
        integrator.u[collect(new_extinct_sp)] .= 0.0
        t = integrator.t
        new_extinct_sp_dict = Dict(sp => t for sp in new_extinct_sp)
        merge!(integrator.p.extinct_sp, new_extinct_sp_dict) # update extinct species list
        # Info message (printed only if verbose = true).
        if verbose && !isempty(new_extinct_sp)
            S, S_ext = length(integrator.u[sp]), length(all_extinct_sp)
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
    terminated = is_terminated(solution)
    steady_state = terminated ? solution.u[end] : nothing
    (steady_state = steady_state, terminated = terminated)
end

# 2023-02-21: Our test suite broke twice this year
# due to breaking updates of DifferentialEquations.jl,
# so better isolate these unstable checks here.
is_terminated(solution) = solution.retcode == ReturnCode.Terminated
is_success(solution) = solution.retcode == ReturnCode.Success

#### end ####

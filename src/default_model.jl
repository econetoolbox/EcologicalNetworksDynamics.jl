# Construct all default base components from the given set of blueprints,
# to make it easier to get a model value ready for simulation.
# Default blueprints can be overriden by listing them as simple arguments,
# and default components are not added if listed within the 'without' keyword argument.


"""
    default_model(
        blueprints...;
        without = ModelComponent[],
    )

Generate a model from a foodweb with parameters set to default values.

Let's first illustrate the use of `default_model` with a simple example.

```julia
foodweb = Foodweb([1 => 2])
default_model(foodweb)
```

In this example, *all* parameters are set to default values,
however for your needs, you can override any of the default parameters.
For instance, if you want to override the default metabolic rate,
you can do it as follows:

```julia
my_x = [0.0, 1.2] # One value per species.
default_model(foodweb, Metabolism(my_x))
```
"""
function default_model(blueprints::Union{Blueprint,BlueprintSum}...; without = Component[])

    N = Nutrients

    # Extract blueprints from their sums.
    blueprints = collect(
        Iterators.flatten(bp isa BlueprintSum ? bp.pack : (bp,) for bp in blueprints),
    )

    # List components that the caller wishes to not automatically add.
    isacomponent(without) && (without = [without]) # (interpret single as singleton)
    checked = []
    for w in without
        isacomponent(w) || argerr("Not a component: $(repr(w)) ::$(typeof(w)).")
        push!(checked, F.component_type(w))
    end
    without = checked

    # List 'hook' blueprints, indexed by the component(s) they provide.
    # These blueprints are consumed if needed, and unless excluded,
    # to fulfill 'required' components or 'expands_from' requirements of other blueprints.
    hooks = Dict{CompType,Blueprint}()
    # TODO: hooks are constrained to yield the same default value regardless of context
    # (eg. whether temperature was given). Improve when this constraint is hit.

    # Gather all blueprints specified by the caller,
    # indexed by the concrete component(s) they provide.
    # These take precedence over the hooks and any default-constructed blueprint.
    input = OrderedDict{CompType,Blueprint}()

    # The two bove collections contain duplicates (aliases)
    # for blueprints providing several components,
    # but it is an error to have different blueprints providing the same.

    # Collect all concrete components about to be eventually added to the returned model.
    # Values represent the corresponding blueprints.
    # Set to 'nothing' for components provided by embedded sub-blueprints.
    final = OrderedDict{CompType,Option{Blueprint}}()

    #---------------------------------------------------------------------------------------
    # Closures specifying local semantics.

    ct = F.component_type

    # A blueprint providing C has been given by the caller.
    given(C) = any(k <: ct(C) for k in keys(input))
    # A blueprint providing C will be used in the result.
    collected(C) = any(k <: ct(C) for k in keys(final))
    # A blueprint providing C is available as a hook.
    hooked(C) = any(k <: ct(C) for k in keys(hooks))
    # The caller wants no C in the result.
    excluded(C) = any(w <: ct(C) for w in without)

    peek_collected(C) = first(final[k] for k in keys(final) if k <: ct(C))

    function take_from_caller!(C)
        C = first(k for k in keys(input) if k <: ct(C))
        bp = input[C]
        for C in F.componentsof(bp)
            pop!(input, C)
        end
        bp
    end

    add_hook!(bp) =
        for C in F.componentsof(bp)
            C in keys(hooks) && throw("Two hooks provide the same component $C:\n
                                       - First: $(hooks[C])\n
                                       - Redundant: $bp\n
                                       This is a bug in the `default_model` function.")
            hooks[C] = bp
        end

    function pop_hook!(C)
        haskey(hooks, C) || return
        bp = hooks[C]
        for C in F.componentsof(bp)
            pop!(hooks, C)
        end
        bp
    end

    # When constructing a default aggregated blueprint,
    # fill brought sub-blueprints from either blueprint sources.
    take_brought!(C, default) =
        if collected(C) || excluded(C)
            nothing # Don't bring.
        else
            bp = if given(C)
                take_from_caller!(C)
            else
                pass_args_kwargs(C, default) # Construct default.
            end
            pop_hook!(C)
            collect_needed!(bp)
            bp
        end

    # Mark embedded components if any.
    function mark_embedded_by!(bp)
        for brought in F.brought(bp)
            brought isa Blueprint || continue
            for B in F.componentsof(brought)
                if collected(B)
                    bp = sprint(F.display_long, bp, 1)
                    alr = sprint(F.display_long, peek_collected(B), 1)
                    B = sprint(Base.show, B)
                    argerr("Blueprint embeds an already given sub-blueprint for $B:\n  \
                             -> The blueprint: $bp\n  \
                             -> Already given: $alr")
                end
                # 'Construct' the brought bueprints
                # to also recursively collect their dependencies.
                collect_needed!(brought)
                final[B] = nothing
            end
        end
    end

    # Collect blueprints required to add dependencies of the given blueprint.
    function collect_needed!(bp)
        # TODO: this mirrors add!(system, blueprint): factorize?
        needed = OrderedSet()
        for (n, _) in F.checked_expands_from(bp)
            push!(needed, n)
        end
        for C in F.componentsof(bp)
            for (n, _) in F.requires(C)
                push!(needed, n)
            end
        end
        for need in needed
            if given(need)
                # Pick from caller input.
                collect!(take_from_caller!(need))
            elseif !collected(need) && !excluded(need) && hooked(need)
                collect!(pop_hook!(need))
            else
                # Ignored: not collected. Possibly already collected, given,
                # or an error will be raised at the user if a component is missing.
            end
        end
    end

    # Commit to adding a blueprint to the result.
    function collect!(bp)
        for C in F.componentsof(bp)
            collected(C) && argerr("Two concurrent blueprints collected. \
                                    This is a bug in the default_model function:\n  \
                                      - $(peek_collected(C))\n  \
                                      - $bp")
        end
        collect_needed!(bp)
        mark_embedded_by!(bp)
        for C in F.componentsof(bp)
            final[C] = bp
        end
    end

    collect_if_given!(C) = given(C) && collect!(take_from_caller!(C))

    # Pick an expected blueprint from user input,
    # unless excluded, or construct a default one.
    function collect_or!(C, make_default)
        # (receive a callback to not consume caller's input
        #  during make_default() evaluation until we can prove it is necessary)
        if !given(C) && !excluded(C) && !collected(C)
            collect!(make_default())
        end
        collect_if_given!(C)
    end

    # ======================================================================================
    # Consistency guards.

    for bp in blueprints
        for C in F.componentsof(bp)
            given(C) && argerr("Two concurrent blueprints given:\n  \
                                  - $(take_from_caller!(C))\n
                                  - $bp")
            excluded(C) && argerr("Component '$C' is excluded \
                                   but the given blueprint provides it: $bp.")
            input[C] = bp
        end
    end

    given(Foodweb) || argerr("No blueprint specified for a foodweb.")

    if given(Temperature)
        fr =
            given(BioenergeticResponse) ? BioenergeticResponse :
            given(LinearResponse) ? LinearResponse : nothing
        isnothing(fr) || argerr("Temperature response is not designed for $fr. \
                                 Use ClassicResponse instead, \
                                 or don't specify a temperature.")
    end

    # ======================================================================================
    # The most structuring nodes and edges compartments, if any, should be expanded first.

    collect_if_given!(Species)
    collect_if_given!(Foodweb)

    # Default to nutrient intake if any nutrient-related blueprint is input.
    nutrients_given = any(
        given(C) for
        C in (N.Nodes, N.Turnover, N.Supply, N.Concentration, N.HalfSaturation)
    )
    collect_if_given!(N.Nodes)

    # Default to ClassicResponse if any NTI layer is input.
    nti_given = given(Nti.Layer)

    #---------------------------------------------------------------------------------------
    # In the next, default blueprints values
    # depend on whether a temperature has been given.

    temperature_given = given(Temperature)
    collect_if_given!(Temperature)

    #---------------------------------------------------------------------------------------
    # Not always required but often missing then.

    add_hook!(BodyMass(; Z = 10))
    add_hook!(MetabolicClass(:all_invertebrates))

    #---------------------------------------------------------------------------------------
    # Producer growth.

    # Construct default blueprints, using the given optional sub-blueprints if any.
    tb! = take_brought!
    collect_or!(
        ProducerGrowth,
        () -> if nutrients_given
            NutrientIntake(;
                r = tb!(GrowthRate, temperature_given ? :Binzer2016 : :Miele2019),
                # Pick defaults from Brose2008.
                nodes = tb!(N.Nodes, (; per_producer = 1)),
                turnover = tb!(N.Turnover, 0.25),
                supply = tb!(N.Supply, 4),
                concentration = tb!(N.Concentration, 0.5),
                half_saturation = tb!(N.HalfSaturation, 0.15),
            )
        elseif temperature_given
            LogisticGrowth(;
                r = tb!(GrowthRate, :Binzer2016),
                K = tb!(CarryingCapacity, :Binzer2016),
                producers_competition = tb!(ProducersCompetition, (; diag = 1)),
            )
        else
            r = tb!(GrowthRate, :Miele2019)
            K = tb!(CarryingCapacity, 1)
            pc = tb!(ProducersCompetition, (; diag = 1))
            LogisticGrowth(; r = r, K = K, producers_competition = pc)
        end,
    )

    #---------------------------------------------------------------------------------------
    # Trophic functional response.

    collect_or!(
        FunctionalResponse,
        () -> if temperature_given
            ClassicResponse(;
                M = nothing,
                e = tb!(Efficiency, :Miele2019),
                h = tb!(HillExponent, 2),
                w = tb!(ConsumersPreferences, :homogeneous),
                c = tb!(IntraspecificInterference, 0),
                attack_rate = tb!(AttackRate, :Binzer2016),
                handling_time = tb!(HandlingTime, :Binzer2016),
            )
        elseif nti_given
            ClassicResponse(;
                M = nothing,
                e = tb!(Efficiency, :Miele2019),
                h = tb!(HillExponent, 2),
                w = tb!(ConsumersPreferences, :homogeneous),
                c = tb!(IntraspecificInterference, 0),
                attack_rate = tb!(AttackRate, :Miele2019),
                handling_time = tb!(HandlingTime, :Miele2019),
            )
        else
            BioenergeticResponse(;
                e = tb!(Efficiency, :Miele2019),
                y = tb!(MaximumConsumption, :Miele2019),
                h = tb!(HillExponent, 2),
                w = tb!(ConsumersPreferences, :homogeneous),
                c = tb!(IntraspecificInterference, 0),
                half_saturation_density = tb!(HalfSaturationDensity, 0.5),
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # Metabolism and death.

    collect_or!(Metabolism, () -> if temperature_given
        Metabolism(:Binzer2016)
    else
        Metabolism(:Miele2019)
    end)

    collect_or!(Mortality, () -> Mortality(0))

    #---------------------------------------------------------------------------------------
    # + any other optional blueprint, in the order specified by the caller.

    while !isempty(input)
        collect!(pop!(input, first(keys(input))))
    end

    # ======================================================================================
    # Construct the model from the collected sequence of blueprints.

    model = Model()

    already = Set() # (avoid duplicated multi-provided blueprints)
    for (_, bp) in final
        isnothing(bp) && continue
        bp in already && continue

        add!(model, bp)

        push!
    end

    model

end
export default_model

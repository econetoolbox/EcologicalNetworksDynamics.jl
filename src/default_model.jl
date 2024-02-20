# Construct all default base components from the given set of blueprints,
# to make it easier to get a model value ready for simulation.
# Default blueprints can be overriden by listing them as simple arguments,
# and default components are not added if listed within the 'without' keyword argument.

function default_model(
    blueprints::Union{ModelBlueprint,ModelBlueprintSum}...;
    without = ModelComponent[],
)

    N = Nutrients

    # Extract blueprints from their sums.
    blueprints = collect(
        Iterators.flatten(bp isa ModelBlueprintSum ? bp.pack : (bp,) for bp in blueprints),
    )

    # List components that the caller wishes to not automatically add.
    without isa ModelComponent && (without = [without]) # (interpret single as singleton)

    # List 'hook' blueprints, indexed by the component they bring.
    # These blueprints are pulled if needed, and unless excluded,
    # to fulfill 'buildsfrom' requirements of other blueprints
    # either given by the caller or generated by default.
    hooks = Dict() #  {component ↦  blueprint}
    # TODO: hooks are constrained to yield the same default value regardless of context
    # (eg. whether temperature was given). Improve when this constraint is hit.

    # Gather all caller-defined components, indexed by the component they bring.
    # These take precedence over the hooks and any default-constructed blueprint.
    input = OrderedDict()

    # Collect all components about to be eventually added to the returned model.
    # Values represent the corresponding blueprints,
    # set to 'nothing' for components brought by other sub-blueprints.
    # Blueprint/components 'implied' are not (yet) listed here.
    final = OrderedDict()

    #---------------------------------------------------------------------------------------
    # Closures specifying local semantics.
    # (the <: relations checks work around current framework semantic flaw)

    # A blueprint for C has been given by the caller.
    given(C) = any(k <: C for k in keys(input))
    # A blueprint for C will be used in the result.
    collected(C) = any(k <: C for k in keys(final))
    # The caller wants no C in the result.
    excluded(C) = any(w <: C for w in without)

    take_from_caller!(C) = pop!(input, first(k for k in keys(input) if k <: C))
    peek_collected(C) = first(final[k] for k in keys(final) if k <: C)
    remove_hook!(C) = haskey(hooks, C) && pop!(hooks, C)

    # When constructing a default blueprints,
    # fill brought sub-blueprints from either blueprint sources.
    function take_brought!(C, default)
        # println("*take_brought!: $C $default")
        if collected(C) || excluded(C)
            # println("  nobring")
            nothing # Don't bring.
        else
            bp = if given(C)
                # println("  take from caller")
                take_from_caller!(C)
            else
                # println("  construct default")
                pass_args_kwargs_to_type(C, default) # Construct default.
            end
            remove_hook!(C)
            collect_needed!(bp)
            bp
        end
    end

    # Mark brought components if any.
    function mark_broughts_by!(bp)
        C = F.componentof(bp)
        # println("*mark_broughts_by!: $C $bp")
        for brought in F.brings(bp)
            B = F.componentof(brought)
            # println("  - $B: $brought")
            collected(B) && argerr("Blueprint for $C brings $B, already given:\n  \
                                     - $C brings: $(F.construct_brought(B, bp))\n  \
                                     - already given: $(peek_collected(B))")
            # 'Construct' the brought bueprints
            # to also recursively collect their dependencies.
            b = F.construct_brought(B, bp) # (actually 'alias_brought' in all current cases)
            collect_needed!(b)
            final[B] = nothing
        end
    end

    # Collect blueprints required to add dependencies of the given blueprint.
    function collect_needed!(bp)
        # TODO: this mirrors add!(system, blueprint): factorize?
        C = F.componentof(bp)
        # println("*collect_needed!: $C $bp")
        for (fn, x) in ((F.requires, C), (F.buildsfrom, bp))
            needed = fn(x)
            for need in needed
                need, _ = need isa Pair ? need : (need, nothing) # (drop the reason)
                # println("  - $need")
                if given(need)
                    # println("    collect from caller")
                    # Pick from caller input.
                    collect!(take_from_caller!(need))
                elseif !collected(need) && !excluded(need) && haskey(hooks, need)
                    # println("    collect from hooks")
                    collect!(pop!(hooks, need))
                else
                    # println("    ignored")
                end
            end
        end
    end

    # Commit to adding a blueprint to the result.
    function collect!(bp)
        C = F.componentof(bp)
        # println("*collect!: $C $bp")
        collected(C) && argerr("Two concurrent blueprints collected. \
                                This is a bug in the default_model function:\n  \
                                  - $(peek_collected(C))\n  \
                                  - $bp")
        collect_needed!(bp)
        mark_broughts_by!(bp)
        final[C] = bp
    end

    collect_if_given!(C) = given(C) && collect!(take_from_caller!(C))

    # Pick an expected blueprint from user input,
    # unless excluded, or construct a default one.
    function collect_or!(C, make_default)
        # (receive a callback to not consume caller's input
        #  during make_default() evaluation until we can prove it is necessary)
        if !given(C) && !excluded(C) && !collected(C)
            # println("*make default $C")
            collect!(make_default())
        end
        collect_if_given!(C)
    end

    # ======================================================================================
    # Consistency guards.

    for bp in blueprints
        C = F.componentof(bp)
        given(C) && argerr("Two concurrent blueprint given:\n  \
                              - $(take_from_caller!(C))\n
                              - $bp")
        excluded(C) && argerr("Component '$C' is excluded \
                               but the given blueprint would expand to it: $bp.")
        input[C] = bp
    end

    given(Foodweb) || argerr("No blueprint specified for a foodweb.")

    if given(Temperature)
        fr =
            given(BioenergeticResponse) ? BioenergeticResponse :
            given(LinearResponse) ? LinearResponse : nothing
        isnothing(fr) || argerr("Temperature response is not designed for $(nameof(fr)). \
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
    nti_given = given(NtiLayer)

    #---------------------------------------------------------------------------------------
    # In the next, default blueprints values
    # depend on whether a temperature has been given.

    temperature_given = given(Temperature)
    collect_if_given!(Temperature)

    #---------------------------------------------------------------------------------------
    # Not always required but often missing.

    hooks[BodyMass] = BodyMass(; Z = 10)
    hooks[MetabolicClass] = MetabolicClass(:all_invertebrates)

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
                nodes = tb!(N.Nodes, :one_per_producer),
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
            LogisticGrowth(;
                r = tb!(GrowthRate, :Miele2019),
                K = tb!(CarryingCapacity, 1),
                producers_competition = tb!(ProducersCompetition, (; diag = 1)),
            )
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

    for (C, bp) in final
        # println("FINAL: $C: $bp")
        isnothing(bp) || add!(model, bp)
    end

    model

end
export default_model

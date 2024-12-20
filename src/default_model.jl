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

    m = Model()

    w(b, C, default) = b(C, () -> pass_args_kwargs(C, default))

    add!(
        m,
        blueprints...;

        # Based on the blueprints input,
        # collect the information required to decide the defaults blueprints to use next.
        defaults_status = given -> begin
            given(Foodweb) || argerr("No blueprint specified for a foodweb.")
            if given(Temperature)
                fr =
                    given(BioenergeticResponse) ? BioenergeticResponse :
                    given(LinearResponse) ? LinearResponse : nothing
                isnothing(fr) ||
                    argerr("Temperature response is not designed for $fr. \
                            Use ClassicResponse instead, \
                            or don't specify a temperature.")
            end
            (;
                temperature = given(Temperature),
                nti = given(Nti.Layer),
                nutrients = any(
                    given(C) for C in
                    (N.Nodes, N.Turnover, N.Supply, N.Concentration, N.HalfSaturation)
                ),
            )
        end,

        # Not always required but often missing then.
        # Automatically introduced if neeeded.
        hooks = [BodyMass(; Z = 10), MetabolicClass(:all_invertebrates)],
        # TODO: hooks are constrained to yield the same default value regardless of context
        # (eg. whether temperature was given). Improve when this constraint is hit.

        defaults = [

            #-------------------------------------------------------------------------------
            ProducerGrowth =>
                (given, b) -> if given.nutrients
                    NutrientIntake(;
                        r = w(b, GrowthRate, given.temperature ? :Binzer2016 : :Miele2019),
                        # Pick defaults from Brose2008.
                        nodes = w(b, N.Nodes, (; per_producer = 1)),
                        turnover = w(b, N.Turnover, 0.25),
                        supply = w(b, N.Supply, 4),
                        concentration = w(b, N.Concentration, 0.5),
                        half_saturation = w(b, N.HalfSaturation, 0.15),
                    )
                elseif given.temperature
                    LogisticGrowth(;
                        r = w(b, GrowthRate, :Binzer2016),
                        K = w(b, CarryingCapacity, :Binzer2016),
                        producers_competition = w(b, ProducersCompetition, (; diag = 1)),
                    )
                else
                    r = w(b, GrowthRate, :Miele2019)
                    K = w(b, CarryingCapacity, 1)
                    pc = w(b, ProducersCompetition, (; diag = 1))
                    LogisticGrowth(; r = r, K = K, producers_competition = pc)
                end,

            #-------------------------------------------------------------------------------
            FunctionalResponse =>
                (given, b) -> if given.temperature
                    ClassicResponse(;
                        M = nothing,
                        e = w(b, Efficiency, :Miele2019),
                        h = w(b, HillExponent, 2),
                        w = w(b, ConsumersPreferences, :homogeneous),
                        c = w(b, IntraspecificInterference, 0),
                        attack_rate = w(b, AttackRate, :Binzer2016),
                        handling_time = w(b, HandlingTime, :Binzer2016),
                    )
                elseif given.nti
                    ClassicResponse(;
                        M = nothing,
                        e = w(b, Efficiency, :Miele2019),
                        h = w(b, HillExponent, 2),
                        w = w(b, ConsumersPreferences, :homogeneous),
                        c = w(b, IntraspecificInterference, 0),
                        attack_rate = w(b, AttackRate, :Miele2019),
                        handling_time = w(b, HandlingTime, :Miele2019),
                    )
                else
                    BioenergeticResponse(;
                        e = w(b, Efficiency, :Miele2019),
                        y = w(b, MaximumConsumption, :Miele2019),
                        h = w(b, HillExponent, 2),
                        w = w(b, ConsumersPreferences, :homogeneous),
                        c = w(b, IntraspecificInterference, 0),
                        half_saturation_density = w(b, HalfSaturationDensity, 0.5),
                    )
                end,

            #-------------------------------------------------------------------------------
            Metabolism => (given, _) -> if given.temperature
                Metabolism(:Binzer2016)
            else
                Metabolism(:Miele2019)
            end,

            #-------------------------------------------------------------------------------
            Mortality => (_, _) -> Mortality(0),
        ],
        without,
    )

    m

end
export default_model

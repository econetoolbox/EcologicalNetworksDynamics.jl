@testset "Metabolic class component." begin

    base = Model(Foodweb([:a => :b, :b => :c]))

    #---------------------------------------------------------------------------------------
    # Construct from aliased values.

    mc = MetabolicClass([:i, :e, :p])
    m = base + mc
    @test m.metabolic_class == [:invertebrate, :ectotherm, :producer]
    @test typeof(mc) == MetabolicClass.Raw

    # With an explicit map.
    ## Integer keys.
    mc = MetabolicClass([2 => :inv, 3 => :ect, 1 => :prod])
    m = base + mc
    @test m.metabolic_class == [:producer, :invertebrate, :ectotherm]
    @test typeof(mc) == MetabolicClass.Map

    ## Symbol keys.
    mc = MetabolicClass([:a => :inv, :b => :ect, :c => :prod])
    m = base + mc
    @test m.metabolic_class == [:invertebrate, :ectotherm, :producer]
    @test typeof(mc) == MetabolicClass.Map

    # Default to homogeneous classes.
    mc = MetabolicClass(:all_ectotherms)
    m = base + mc
    @test m.metabolic_class == [:ectotherm, :ectotherm, :producer]
    mc = MetabolicClass(:all_invertebrates)
    m = base + mc
    @test m.metabolic_class == [:invertebrate, :invertebrate, :producer]
    @test typeof(mc) == MetabolicClass.Favor

    # Editable property.
    m.metabolic_class[2] = "e" # Conversion on.
    @test m.metabolic_class == [:invertebrate, :ectotherm, :producer]
    m.metabolic_class[1:2] .= :inv
    @test m.metabolic_class == [:invertebrate, :invertebrate, :producer]

    #---------------------------------------------------------------------------------------
    # Input guards.

    @sysfails(
        base + MetabolicClass([:i, :x]),
        Check(
            early,
            [MetabolicClass.Raw],
            "Invalid reference in aliasing system for \"metabolic class\": class[2] = :x",
        )
    )

    @sysfails(
        base + MetabolicClass([:a => :i, :b => :x]),
        Check(
            early,
            [MetabolicClass.Map],
            "Invalid reference in aliasing system for \"metabolic class\": class[:b] = :x",
        )
    )

    @sysfails(
        base + MetabolicClass(:invalid_favor),
        Check(
            early,
            [MetabolicClass.Favor],
            "Invalid symbol received for 'favourite': :invalid_favor. \
             Expected either :all_invertebrates or :all_ectotherms instead.",
        )
    )

    # Checked against the foodweb.
    @sysfails(
        base + MetabolicClass([:p, :e, :i]),
        Check(
            late,
            [MetabolicClass.Raw],
            "Metabolic class for species :a cannot be 'p' since it is a consumer.",
        )
    )

    @sysfails(
        base + MetabolicClass([:i, :e, :inv]),
        Check(
            late,
            [MetabolicClass.Raw],
            "Metabolic class for species :c cannot be 'inv' since it is a producer.",
        )
    )

    # Requires a foodweb to be checked against.
    @sysfails(
        Model(MetabolicClass([:i, :e, :p])),
        Missing(Foodweb, MetabolicClass, [MetabolicClass.Raw], nothing),
    )

    #---------------------------------------------------------------------------------------
    # Edition guards.

    @failswith(
        (m.metabolic_class[2] = 4),
        EN.Views.WriteError(
            "Invalid reference in aliasing system for \"metabolic class\"",
            :metabolic_class,
            2,
            4,
        ),
    )

    @failswith(
        (m.metabolic_class[2] = :p),
        EN.Views.WriteError(
            "Metabolic class for species :b cannot be 'producer' since it is a consumer.",
            :metabolic_class,
            2,
            :p,
        ),
    )

    @failswith(
        (m.metabolic_class[:c] = :i),
        EN.Views.WriteError(
            "Metabolic class for species :c cannot be 'invertebrate' since it is a producer.",
            :metabolic_class,
            :c,
            :i,
        ),
    )

end

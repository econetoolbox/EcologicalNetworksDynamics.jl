module MetabolicClassTest

using EcologicalNetworksDynamics

using Test
using EcologicalNetworksDynamics: F, N
using Main: is_repr, is_disp, @inputfails, @writefails, @sysfails, Value

@testset "Metabolic class component." begin

    base = Model(Foodweb([:a => :b, :b => :c]))

    # Values are symbols, checked and expanded against aliasing dict.
    bp = MetabolicClass(collect("iep"))
    @test bp.metabolic_class == [:i, :e, :p]
    m = base + bp
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 3 (:a, :b, :c)
          - Foodweb: 2 links, 1 producer, 2 consumers, 2 preys, 1 top.
          - MetabolicClass: [:invertebrate, :ectotherm, :producer]\
        """,
    )
    @test m.metabolic_class == [:invertebrate, :ectotherm, :producer]

    # Mutable classes, with expansion/conversion on.
    m.metabolic_class[1] = :e
    m.metabolic_class[:b] = 'i'
    @test m.metabolic_class == [:ectotherm, :invertebrate, :producer]

    # Checked against the *whole model* for consistency.
    # NOTE: This is where per-value late_checking is tested (irrelevant for body_mass).
    for (Bp, invalid) in [
        (MetabolicClass.Raw, [:p, :p, :p]),
        (MetabolicClass.Map, [:a => :p, :b => :p, :c => :p]),
        (MetabolicClass.Map, [1 => :p, 2 => :p, 3 => :p]),
    ]
        @sysfails(
            (base + MetabolicClass(invalid)),
            Check(
                late,
                [Bp],
                """
                When checking <species:metabolic_class> blueprint values against model:
                At node with label :a ([1]):
                Metabolic class for species :a cannot be :producer since it is a consumer.\
                """,
            )
        )
    end
    for (Bp, invalid) in [
        (MetabolicClass.Raw, [:e, :e, :e]),
        (MetabolicClass.Map, [:a => :e, :b => :e, :c => :e]),
        (MetabolicClass.Map, [1 => :e, 2 => :e, 3 => :e]),
    ]
        @sysfails(
            (base + MetabolicClass(invalid)),
            Check(
                late,
                [Bp],
                """
                When checking <species:metabolic_class> blueprint values against model:
                At node with label :c ([3]):
                Metabolic class for species :c cannot be :ectotherm since it is a producer.\
                """,
            )
        )
    end

    # Even during late edition.
    @writefails(
        m.metabolic_class[:c] = :i,
        metabolic_class[:c] = :i,
        """
        When attempting to mutate <species:metabolic_class> node field:
        At node with label :c ([3]):
        Metabolic class for species :c cannot be :invertebrate since it is a producer.\
        """
    )
    @writefails(
        m.metabolic_class[:a] = :p,
        metabolic_class[:a] = :p,
        """
        When attempting to mutate <species:metabolic_class> node field:
        At node with label :a ([1]):
        Metabolic class for species :a cannot be :producer since it is a consumer.\
        """
    )

    # No flat component. But a 'Favourite' instead.
    bp = MetabolicClass(:all_ectotherms)
    @test bp == MetabolicClass.Favour(:all_ectotherms)
    @test is_repr(bp, "<MetabolicClass>:Favour(favourite: :all_ectotherms)")
    @test is_disp(
        bp,
        """
         blueprint for <MetabolicClass>: Favour {
           favourite: :all_ectotherms,
         }\
        """,
    )
    m = base + bp
    @test m.metabolic_class == [:ectotherm, :ectotherm, :producer]
    bp.favourite = :all_invertebrates
    @test (base + bp).metabolic_class == [:invertebrate, :invertebrate, :producer]
    @inputfails(
        MetabolicClass(:whatever),
        "Expected one of :all_invertebrates or :all_ectotherms.",
        :whatever,
    )
    bp.favourite = :corrupted # (possible after blueprint creation)
    @sysfails(
        (base + bp),
        Check(
            early,
            [MetabolicClass.Favour],
            "Expected one of :all_invertebrates or :all_ectotherms.\n\
             Received: :corrupted",
        )
    )

    # Requires a foodweb to be checked against.
    @sysfails(
        Model(MetabolicClass([:i, :e, :p])),
        Missing(Foodweb, MetabolicClass, [MetabolicClass.Raw], nothing),
    )

end

end

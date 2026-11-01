module MetabolicClassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.Tests:
    F, N, D, @test_repr, @test_disp, @test_err, @bpfails, @mutfails, addfails
using Test

const d, _D = D.NodeField(:species, :metabolic_class)

@testset "Metabolic class component." begin

    base = Model(Foodweb([:a => :b, :b => :c]))

    # Values are symbols, checked and expanded against aliasing dict.
    input = [:i, :e, :p]
    bp = MetabolicClass(input)
    @test bp.class === input # (although aliasing keeps holding through construction).
    m = base + bp # Only then does symbols expansion happen.
    @test_disp(m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 3 (:a, :b, :c)
          - Foodweb: 2 links, 1 producer, 2 consumers, 2 preys, 1 top.
          - MetabolicClass: [:invertebrate, :ectotherm, :producer]\
        """)
    @test m.metabolic_class == [:invertebrate, :ectotherm, :producer]

    # Mutable classes, with expansion/conversion on.
    m.metabolic_class[1] = :e
    m.metabolic_class[:b] = 'i'
    @test m.metabolic_class == [:ectotherm, :invertebrate, :producer]

    # Checked against the *whole model* for consistency.
    # NOTE: This is where per-value late_checking is tested (irrelevant for body_mass).
    addfails.@check(base + MetabolicClass([:p, :i, :e]), [],
        (MetabolicClass.Raw, :late,
            (d, :producer, (:m, ((1, :a),)),
                "Metabolic class cannot be :producer for a consumer species.")))
    addfails.@check(base + MetabolicClass([:a => :i, :c => :e, :b => :p]), [],
        (MetabolicClass.Map, :late,
            (d, :producer, (:m, ((2, :b),)),
                "Metabolic class cannot be :producer for a consumer species.")))
    addfails.@check(base + MetabolicClass([1 => :i, 3 => :e, 2 => :i]), [],
        (MetabolicClass.Map, :late,
            (d, :ectotherm, (:m, ((3, :c),)),
                "Metabolic class cannot be :ectotherm for a producer species.")))

    @test_err(base + MetabolicClass([:p, :i, :e]), # First report rendering `mref`.
        """
        Blueprint cannot expand against current system value:
        While verifying blueprint against model:
        In the provided input targetting node value [1] (:a) for <species:metabolic_class>:
        Metabolic class cannot be :producer for a consumer species.
        Received: :producer  ::Symbol
        Not all blueprints have been expanded.
        This means that the system consistency is still guaranteed, \
        but some components have not been added.
        in MetabolicClass.Raw\
        """)

    # Also checked on mutation pipeline.
    @mutfails(m.metabolic_class[:c] = :i,
        (d, :invertebrate, (:m, ((3, :c),)),
            "Metabolic class cannot be :invertebrate for a producer species.")
    )
    @mutfails(m.metabolic_class[:a] = :p,
        (d, :producer, (:m, ((1, :a),)),
            "Metabolic class cannot be :producer for a consumer species."))

    # ======================================================================================
    # No flat component. But a 'Favourite' instead.

    bp = MetabolicClass(:all_ectotherms)

    @test bp == MetabolicClass.Favour(:all_ectotherms)
    @test_repr(bp, "<MetabolicClass>:Favour(favourite: :all_ectotherms)")
    @test_disp(bp,
        """
         blueprint for <MetabolicClass>: Favour {
           favourite: :all_ectotherms,
         }\
        """)

    m = base + bp
    @test m.metabolic_class == [:ectotherm, :ectotherm, :producer]

    bp.favourite = :all_invertebrates
    @test (base + bp).metabolic_class == [:invertebrate, :invertebrate, :producer]

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(MetabolicClass(:whatever),
        MetabolicClass.Favour, :construct,
        (d, :whatever, :uwhole,
            "Expected one of :all_invertebrates or :all_ectotherms."))

    bp.favourite = :corrupted

    addfails.@check((base + bp), [],
        (MetabolicClass.Favour, :early,
            (d, :corrupted, :uwhole,
                "Expected one of :all_invertebrates or :all_ectotherms.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    # Requires a foodweb to be checked against.
    addfails.@missingrequired(Model(MetabolicClass([:i, :e, :p])),
        Foodweb, MetabolicClass, [MetabolicClass.Raw], nothing)

end

end

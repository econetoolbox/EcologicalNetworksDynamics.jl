module TestAliasingDicts

using EcologicalNetworksDynamics.AliasingDicts

using Test
using Main: @argfails, @aliasfails, @xaliasfails, @failswith

const AD = AliasingDicts

# Leverage `repr` summarize most tested features within a single string comparison.
macro check(xp, expected, type)
    quote
        d = $(esc(xp))
        @test $expected == repr(d)
        @test d isa FruitDict{$type}
    end
end

@testset "Aliased references" begin

    #---------------------------------------------------------------------------------------
    # Construct an aliasing dict subtype.
    # with all associated methods.

    @aliasing_dict(FruitDict, "fruit", :fruit, (:apple => [:a], :berry => [:b, :br]))

    F = FruitDict
    @test length(F) == 2

    # Original order is conserved.
    @test AD.standards(F) == (:apple, :berry)

    # Shortest then lexicographic.
    @test AD.references(F) == (apple = (:a, :apple), berry = (:b, :br, :berry))
    @test collect(AD.all_references(F)) == [:a, :apple, :b, :br, :berry]

    # Reverse mapping (shortest then lexicographic).
    @test AD.revmap(F) ==
          (a = :apple, apple = :apple, b = :berry, br = :berry, berry = :berry)

    # Cheat-sheet.
    @test AD.aliases(F) == AD.OrderedDict(:apple => [:a], :berry => [:b, :br])

    @test AD.name(F) == "fruit"

    @test AD.standardize('a', F) == :apple
    @test AD.standardize(:br, F) == :berry

    # Test references equivalence.
    @test AD.is(:br, :berry, F)
    @test !AD.is(:b, :apple, F)

    # Find in iterable.
    @test AD.isin(:b, (:berry, :apple), F)

    @test AD.shortest(:apple, F) == :a

    # Guard against invalid or ambiguous referencing.
    @aliasfails(AD.standardize(:xy, F), "fruit", "Invalid reference: 'xy'.")
    @xaliasfails(
        @aliasing_dict(
            FruitDict_dsr,
            "fruit",
            :fruit,
            (:peach => [:p, :h], :pear => [:r, :p])
        ),
        "fruit",
        "Ambiguous fruit reference: 'p' either means 'peach' or 'pear'.",
    )
    @xaliasfails(
        @aliasing_dict(
            FruitDict_eas,
            "fruit",
            :fruit,
            (:peach => [:h, :e], :pear => [:p, :p]),
        ),
        "fruit",
        "Duplicated fruit alias for 'pear': 'p'.",
    )

    # Fit into the type system.
    @test FruitDict <: AbstractDict
    @test FruitDict{Any} <: AbstractDict{Symbol,Any}
    @test FruitDict{Int64} <: AbstractDict{Symbol,Int64}

    # Construct with or without an explicit type, concrete or abstract.
    # If heterogeneous, the values type is inferred to the less abstract common type.
    # Keys are implicitly converted to symbols if possible.

    # Empty.
    @check FruitDict() "$FruitDict{Any}()" Any
    @check FruitDict{Int64}() "$FruitDict{Int64}()" Int64
    @check FruitDict{Real}() "$FruitDict{Real}()" Real

    # With single kwarg.
    @check FruitDict(; a = 5.0) "$FruitDict{Float64}(a: 5.0)" Float64
    @check FruitDict{Int64}(; a = 5.0) "$FruitDict{Int64}(a: 5)" Int64 # (conversion)
    @check FruitDict{Real}(; a = 5.0) "$FruitDict{Real}(a: 5.0)" Real # (retained abstract)

    # With single arg.
    @check FruitDict(:a => 5.0) "$FruitDict{Float64}(a: 5.0)" Float64
    @check FruitDict('a' => 5.0) "$FruitDict{Float64}(a: 5.0)" Float64
    @check FruitDict{Int64}(:a => 5.0) "$FruitDict{Int64}(a: 5)" Int64
    @check FruitDict{Int64}('a' => 5.0) "$FruitDict{Int64}(a: 5)" Int64 # (key conversion)
    @check FruitDict{Real}(:a => 5.0) "$FruitDict{Real}(a: 5.0)" Real
    @check FruitDict{Real}("a" => 5.0) "$FruitDict{Real}(a: 5.0)" Real# (key conversion)

    # With double kwargs.
    @check FruitDict(; a = 5, b = 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real
    @check FruitDict{Int64}(; a = 5, b = 8.0) "$FruitDict{Int64}(a: 5, b: 8)" Int64
    @check FruitDict{Real}(; a = 5, b = 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real

    # With double args.
    @check FruitDict(:a => 5, :b => 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real
    @check FruitDict('a' => 5, "b" => 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real
    @check FruitDict{Int64}(:a => 5, :b => 8.0) "$FruitDict{Int64}(a: 5, b: 8)" Int64
    @check FruitDict{Int64}('a' => 5, "b" => 8.0) "$FruitDict{Int64}(a: 5, b: 8)" Int64
    @check FruitDict{Real}(:a => 5, :b => 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real
    @check FruitDict{Real}('a' => 5, "b" => 8.0) "$FruitDict{Real}(a: 5, b: 8.0)" Real

    # Guard against ambiguities.
    @aliasfails(
        FruitDict(:a => 5, :b => 8.0, :berry => 7.0),
        "fruit",
        "Fruit type 'berry' specified twice: once with 'b' and once with 'berry'.",
    )

    # Entries are (re)-ordered to standard order.
    @test collect(keys(FruitDict(; b = 8.0, a = 5))) == [:apple, :berry]

    # Index with anything consistent.
    d = FruitDict(:a => 5, :b => 8)
    @test (d[:a], d[:apple], d['a'], d["apple"]) == (5, 5, 5, 5)

    # Set values.
    d[:a] = 42
    @test d[:apple] == 42

    @test haskey(d, :b)
    @test haskey(d, :berry)

    # Guard against inconsistent entries.
    @aliasfails(d[:xy], "fruit", "Invalid reference: 'xy'.")

    # Access underlying aliasing system methods from the instance..
    @test AD.name(d) == "fruit"
    @test collect(AD.references(d)) == [(:a, :apple), (:b, :br, :berry)]
    @test collect(AD.references(:br, d)) == [:b, :br, :berry]
    @test (AD.isref(:b, d), AD.isref(:xy, d)) == (true, false)
    @test AD.shortest(:berry, d) == :b
    @test (AD.standardize(:br, d), AD.standardize(:apple, d)) == (:berry, :apple)

end

# These two need to live in global space for the next test set.
function check_mix_arguments(all_args, _implicit_fruit, _implicit_prop)
    given(fruit, prop) = haskey(all_args[fruit], prop)
    if given(:a, :c) && given(:b, :d)
        all_args[:apple][:color][2] > 1 && all_args[:berry][:depth][2] < 10 ||
            throw(ArgumentError("Berry too deep for a dark apple."))
    end
end
mix_types = nothing

# ==========================================================================================
@testset "Nested 2D API" begin

    # Nest fruit and properties.
    @aliasing_dict(PropertyDict, "property", :prop, (:color => [:c, :col], :depth => [:d]))

    # Specify type template.
    F, P = FruitDict, PropertyDict
    # Use 4 different-yet-related types to check nested type promotions.
    global mix_types = F(;
        apple = P(; color = Int32, depth = Int64),
        berry = P(; color = Float32, depth = Float64),
    )

    @prepare_2D_api(Mix, FruitDict, PropertyDict)

    # These are now defined.
    MA = MixArguments
    TD = TrackedPropDict
    TDS = TD{Signed} # Common type for apple.
    TDF = TD{AbstractFloat} # Common type for berry.
    nocontext(; kwargs...) = parse_mix_arguments(kwargs)
    with_prop(p; kwargs...) = parse_fruit_for_prop(p, kwargs)
    with_fruit(f; kwargs...) = parse_prop_for_fruit(f, kwargs)

    BA = AD.BasalArg{F,P}
    RB = AD.RevBasalArg{F,P}
    NA = AD.NestedArg{F,P}
    RN = AD.RevNestedArg{F,P}
    OC = AD.OuterContextArg{F,P}
    IC = AD.InnerContextArg{F,P}

    # No arguments yield empty data with correct structure.
    args = nocontext()
    @test args == MA(; apple = TDS(), berry = TDF())
    @test typeof(args) === MA
    @test all(typeof.(values(args)) .=== [TD{Signed}, TD{AbstractFloat}])

    # Index 2D information via arguments name.
    args = nocontext(; a_col = 5)
    @test args == MA(;
        apple = TDS(; color = (BA(:a, :col), 5)), # <- Information stored/converted here,
        berry = TDF(),         # ^^^^^^^^^^------------- recalling how it has been input.
    )
    @test args[:a][:c][2] isa Int32 # Casted to expected type.

    # Synonym (reversed base argument).
    args = nocontext(; col_a = 5)
    @test args == MA(; apple = TDS(; color = (RB(:a, :col), 5)), berry = TDF())
    @test args[:a][:c][2] isa Int32

    # Target another "cell" in this (fruit × property) "matrix".
    args = nocontext(; a_col = 5, depth_berry = 8)
    @test args == MA(;
        apple = TDS(; color = (BA(:a, :col), 5)),
        berry = TDF(; depth = (RB(:berry, :depth), 8)), # <- New.
    )
    @test args[:a][:c][2] isa Int32
    @test args[:b][:d][2] isa Float64

    # Target several cells at once (fruit-wise).
    args = nocontext(; apple = (col = 5, d = 8))
    @test args == MA(;
        apple = TDS(; color = (NA(:apple, :col), 5), depth = (NA(:apple, :d), 8)),
        berry = TDF(),
    )
    @test args[:a][:c][2] isa Int32
    @test args[:a][:d][2] isa Int64 # Property type changes with the fruit.

    # Target several cells at once (property-wise).
    args = nocontext(; color = (a = 5, br = 8))
    @test args == MA(;
        apple = TDS(; color = (RN(:a, :color), 5)),
        berry = TDF(; color = (RN(:br, :color), 8)),
    )
    @test args[:a][:c][2] isa Int32
    @test args[:b][:c][2] isa Float32

    # Also works with dynamic dict form.
    dyn = Dict(:col => 5, :d => 8)
    args = nocontext(; apple = dyn)
    @test args == MA(;
        apple = TDS(; color = (NA(:apple, :col), 5), depth = (NA(:apple, :d), 8)),
        berry = TDF(),
    )
    @test args[:a][:c][2] isa Int32
    @test args[:a][:d][2] isa Int64

    dyn = Dict(:a => 5, :br => 8)
    args = nocontext(; depth = dyn)
    @test args == MA(;
        apple = TDS(; depth = (RN(:a, :depth), 5)),
        berry = TDF(; depth = (RN(:br, :depth), 8.0)),
    )
    @test args[:a][:d][2] isa Int64
    @test args[:b][:d][2] isa Float64

    # Simpler "1D" forms with implicit fruit/property.
    # With inner context.
    args = with_prop(:d; a = 5, b = 5)
    @test args == FruitDict(; apple = (IC(:a, :d), 5.0), berry = (IC(:b, :d), 5))
    @test args[:a][2] isa Int64
    @test args[:b][2] isa Float64

    # Correct common type.
    @test typeof(args).parameters[1].parameters[2] === Real

    # With outer context.
    args = with_fruit(:b; c = 5, d = 8)
    @test args == PropertyDict(; color = (OC(:b, :c), 5), depth = (OC(:b, :d), 8))
    @test args[:c][2] isa Float32
    @test args[:d][2] isa Float64
    @test typeof(args).parameters[1].parameters[2] === AbstractFloat

    #---------------------------------------------------------------------------------------
    # Guard against invalid input.

    @argfails(
        nocontext(x = 5),
        "Could not recognize 'fruit' or 'property' within argument name 'x'.",
    )
    @aliasfails(with_prop(:x, a = 5), "property", "Invalid reference: 'x'.",)
    @aliasfails(with_prop(:a, b = 5), "property", "Invalid reference: 'a'.",)
    @aliasfails(with_fruit(:x, d = 5), "fruit", "Invalid reference: 'x'.",)
    @aliasfails(with_fruit(:c, d = 5), "fruit", "Invalid reference: 'c'.",)

    @argfails(
        nocontext(apple = 5),
        "Fruit argument 'apple' cannot be iterated as (property=value,) pairs: \
         integer keys.",
    )

    @argfails(
        with_fruit(:apple, color = (a = "text",)),
        "Could not convert or adapt input at (:apple, :color) from 'color' argument \
         with value: (a = \"text\",).\n\
         Expected type   : Int32\n\
         Received instead: @NamedTuple{a::String}",
    )

    @argfails(
        with_prop(:color, apple = (a = "text",)),
        "Could not convert or adapt input at (:apple, :color) from 'apple' argument \
         with value: (a = \"text\",).\n\
         Expected type   : Int32\n\
         Received instead: @NamedTuple{a::String}",
    )

    @aliasfails(nocontext(color = (x = 5,)), "fruit", "Invalid reference: 'x'.",)

    @aliasfails(nocontext(apple = (berry = 5,)), "property", "Invalid reference: 'berry'.",)

    @aliasfails(nocontext(color = (depth = 5,)), "fruit", "Invalid reference: 'depth'.",)

    @argfails(
        nocontext(apple = (color = 5)),
        "Fruit argument 'apple' cannot be iterated as (property=value,) pairs: \
         integer keys.",
    )

    # Catch redundant specifications.
    @argfails(
        nocontext(apple = (color = 5, c = 8)),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'c' within a 'apple' argument, \
         but it has already been specified \
         as 'color' within a 'apple' argument. \
         Consider removing either one.",
    )

    @argfails(
        nocontext(apple = (color = 5,), c = (a = 8,)),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'a' within a 'c' argument, \
         but it has already been specified \
         as 'color' within a 'apple' argument. \
         Consider removing either one.",
    )

    @argfails(
        nocontext(apple = (color = 5,), a = (c = 8,)),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'c' within a 'a' argument, \
         but it has already been specified \
         as 'color' within a 'apple' argument. \
         Consider removing either one.",
    )

    @argfails(
        nocontext(apple = (color = 5,), c_a = 8),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'c_a' argument, \
         but it has already been specified \
         as 'color' within a 'apple' argument. \
         Consider removing either one.",
    )

    @argfails(
        nocontext(apple = (color = 5,), a_c = 8),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'a_c' argument, \
         but it has already been specified \
         as 'color' within a 'apple' argument. \
         Consider removing either one.",
    )

    @argfails(
        nocontext(apple_color = 5, a_c = 8),
        "Ambiguous or redundant specification in aliased 2D input for 'Mix': \
         'apple' value for 'color' is specified \
         as 'a_c' argument, \
         but it has already been specified \
         as 'apple_color' argument. \
         Consider removing either one.",
    )

    # Use additional semantic checks.
    @argfails(
        nocontext(apple_color = 1, berry_depth = 15),
        "Berry too deep for a dark apple."
    )

    #---------------------------------------------------------------------------------------
    # Guard nested 2D api *devs* against possible ambiguous input.
    # (use random trigrams as api names to not have tests interact with each other)

    @aliasing_dict(SneakDict_jpc, "sneak", :sneak, (:ambiguous => [:a],))
    global tfi_types = nothing # (dummy)
    @failswith(
        @prepare_2D_api(Tfi, FruitDict, SneakDict_jpc),
        "Ambiguous aliasing for 'Tfi' 2D API: \
         argument 'a' either means 'fruit::apple' or 'sneak::ambiguous'."
    )
    global euz_types = nothing
    @failswith(
        @prepare_2D_api(Euz, SneakDict_jpc, FruitDict),
        "Ambiguous aliasing for 'Euz' 2D API: \
         argument 'a' either means 'sneak::ambiguous' or 'fruit::apple'."
    )

    @aliasing_dict(
        SneakDict_sys,
        "sneak",
        :sneak,
        (:dummy => [:d], :alter_daemon => [:a_d])
    )
    global ycd_types = nothing # (dummy)
    @failswith(
        @prepare_2D_api(Ycd, FruitDict, SneakDict_sys),
        "Ambiguous aliasing for 'Ycd' 2D API: \
         argument 'a_d' either means 'sneak::alter_daemon' \
         or 'sneak::dummy' within 'fruit::apple'."
    )
    global rig_types = nothing
    @failswith(
        @prepare_2D_api(Rig, SneakDict_sys, FruitDict),
        "Ambiguous aliasing for 'Rig' 2D API: \
         argument 'a_d' either means 'sneak::alter_daemon' \
         or 'fruit::apple' within 'sneak::dummy'."
    )

    @aliasing_dict(
        SneakDict_iae,
        "sneak",
        :sneak,
        (:dummy => [:d], :direct_attack => [:d_a])
    )
    global bbt_types = nothing
    @failswith(
        @prepare_2D_api(Bbt, FruitDict, SneakDict_iae),
        "Ambiguous aliasing for 'Bbt' 2D API: \
         argument 'd_a' either means 'sneak::direct_attack' \
         or 'sneak::dummy' within 'fruit::apple'."
    )
    global daz_types = nothing
    @failswith(
        @prepare_2D_api(Daz, SneakDict_iae, FruitDict),
        "Ambiguous aliasing for 'Daz' 2D API: \
         argument 'd_a' either means 'sneak::direct_attack' \
         or 'fruit::apple' within 'sneak::dummy'."
    )

end

end

"Test the system behaviour when correcty setup by framework users = lib authors."
module AuthorLib

using EcologicalNetworksDynamics: F

# The aggregate value to wrap in a "system" in subsequent tests.
# (loosely inspired from a 'dataframe': indexed collection of vectors of same length.
mutable struct Value
    _n::Int64
    _dict::Dict{Symbol,Any}
    Value() = new(0, Dict())
end
Base.copy(v::Value) = deepcopy(v)
# Willing to enjoy wrapped value properties.
Base.getproperty(v::Value, p::Symbol) = F.unchecked_getproperty(v, p)
Base.setproperty!(v::Value, p::Symbol, rhs) = F.unchecked_setproperty!(v, p, rhs)

struct CheckError <: F.InputError
    mess::String
end
F.message(e::CheckError) = e.mess
checkfails(mess) = throw(CheckError(mess))

# ==========================================================================================
# Define basic blueprints/components to work with the above value.

module Basics # Use submodules to not clash blueprints/components names.

    import ..AuthorLib: Value, checkfails

    import EcologicalNetworksDynamics.Framework:
        Framework, F, Blueprint, define_blueprint, define_component, define_method,
        define_conflicts, has_component

    #---------------------------------------------------------------------------------------
    # One component/blueprint for the number of lines.
    mutable struct NLines <: Blueprint{Value}
        n::Int64
    end
    F.early_check(nl::NLines) =
        nl.n > 0 || checkfails("Not a positive number of lines: $(nl.n).")
    F.expand!(s, nl::NLines) = (F.value(s)._n = nl.n)
    define_blueprint(NLines)
    define_component(:Size, Value, Basics; blueprints = [:N => NLines])
    local Size, _Size # (reassure JuliaLS)

    get_n(v::Value) = v._n
    define_method(get_n; depends = [Size], read_as = [:n])

    #---------------------------------------------------------------------------------------
    # One component to bring 'a' data.
    # Various blueprints bring it, gathered within a module.

    module ABlueprints # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

        import ..Basics: Value, Size, _Size, NLines, checkfails

        import EcologicalNetworksDynamics.Framework:
            F, Blueprint, define_blueprint

        mutable struct Uniform <: Blueprint{Value}
            value::Float64
        end
        F.expand!(s, u::Uniform) = (F.value(s)._dict[:a] = [u.value for _ in 1:s.n])
        define_blueprint(Uniform)

        mutable struct Raw <: Blueprint{Value}
            a::Vector{Float64}
        end
        F.implied(::Raw) = (_Size,)
        F.implied_blueprint_for(r::Raw, ::Type{_Size}) = NLines(length(r.a))
        function F.late_check(s, raw::Raw)
            na = length(raw.a)
            nv = s.n
            na == nv || checkfails("Cannot expand $na 'a' values into $nv lines.")
        end
        F.expand!(s, r::Raw) = (F.value(s)._dict[:a] = deepcopy(r.a))
        define_blueprint(Raw)

    end # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # The component gathers all blueprints from the above module.
    define_component(
        :A,
        Value,
        Basics;
        requires = [Size],
        blueprints = [:Uniform => ABlueprints.Uniform, :Raw => ABlueprints.Raw],
    )
    local A # (reassure JuliaLS)
    get_a(v::Value) = v._dict[:a]
    define_method(get_a; depends = [A], read_as = [:a])

    #---------------------------------------------------------------------------------------
    # One component to bring 'b' data,
    # depending on the 'a' data in that all values must be greater than 'a', say.

    module BBlueprints # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

        import ..Basics: Basics, Value, Size, _Size, NLines, checkfails

        import EcologicalNetworksDynamics.Framework:
            F, Blueprint, define_blueprint


        mutable struct Uniform <: Blueprint{Value}
            value::Float64
        end
        F.late_check(s, u::Uniform) =
            maximum(s.a) <= u.value ||
            checkfails("Values 'b' not larger than maximum 'a' values.")
        F.expand!(s, u::Uniform) = (F.value(s)._dict[:b] = [u.value for _ in 1:s.n])
        define_blueprint(Uniform)

        mutable struct Raw <: Blueprint{Value}
            b::Vector{Float64}
        end
        function F.late_check(v, raw::Raw)
            nb = length(raw.b)
            nv = v.n
            nb == nv || checkfails("Cannot expand $nb 'a' values into $nv lines.")
            maximum(v.a) <= minimum(raw.b) || checkfails("Values 'b' too small wrt 'a'.")
        end
        F.expand!(s, r::Raw) = (F.value(s)._dict[:b] = deepcopy(r.b))
        Basics.NLines(r::Raw) = NLines(length(r.b))
        F.implied(::Raw) = (Size,) # (also works with singleton instance)
        F.implied_blueprint_for(r::Raw, ::Type{_Size}) = NLines(length(r.b))
        define_blueprint(Raw)

    end # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    define_component(
        :B,
        Value,
        Basics;
        requires = [Size, A],
        blueprints = [:Uniform => BBlueprints.Uniform, :Raw => BBlueprints.Raw],
    )
    local B # (reassure JuliaLS)
    get_b(v::Value) = v._dict[:b]
    define_method(get_b; depends = [B], read_as = [:b])

    # One method that uses both components.
    get_sum(v::Value) = v.a .+ v.b
    define_method(get_sum; depends = [A, B], read_as = [:sum])

    #---------------------------------------------------------------------------------------
    # One 'marker' component incompatible with others.

    struct SparseMark <: Blueprint{Value} end
    define_blueprint(SparseMark)
    define_component(:Sparse, Value, Basics; blueprints = [:Mark => SparseMark])
    define_conflicts(Sparse, Size)
    local Sparse # (reassure JuliaLS)

    #---------------------------------------------------------------------------------------
    # One component whose expansion/checking depends on other components within the system.

    struct ReflectionMark <: Blueprint{Value} end
    F.late_check(s, ::ReflectionMark) =
        if !has_component(s, A) && !has_component(s, B)
            checkfails("Cannot reflect from no data.")
        end
    function F.expand!(s, ::ReflectionMark)
        rf = Char[]
        if has_component(s, A)
            push!(rf, 'A')
        end
        if has_component(s, B)
            push!(rf, 'B')
        end
        rf = collect(Iterators.take(Iterators.cycle(rf), s.n))
        F.value(s)._dict[:reflection] = rf
    end
    define_blueprint(ReflectionMark)

    # This alternate blueprint
    # does not bring data that *don't make sense* without A,
    # so it does not *require* A,
    # but it needs A to expand.
    struct ReflectFromB <: Blueprint{Value} end
    function F.expand!(s, ::ReflectFromB)
        F.value(s)._dict[:reflection] =
            collect(first.(repr.(Iterators.take(Iterators.cycle(s.a), s.n))))
    end
    define_blueprint(ReflectFromB; depends = [A])
    define_component(
        :Reflection,
        Value,
        Basics;
        requires = [Size],
        blueprints = [:Mark => ReflectionMark, :B => ReflectFromB],
    )
    local Reflection # (reassure JuliaLS)

    # Read property with aliases.
    get_reflection(v::Value) = v._dict[:reflection]
    define_method(get_reflection; depends = [Reflection], read_as = [:reflection, :ref])

    # One writeable property.
    function set_reflection!(v::Value, rhs::String)
        v._dict[:reflection] = collect(Iterators.take(Iterators.cycle(rhs), v.n))
    end
    define_method(set_reflection!; depends = [Reflection], write_as = [:reflection, :ref])

    # ======================================================================================
    # Test actual use of the system.

    # (what lib authors would need)
    import EcologicalNetworksDynamics.Framework: Component, System, add!

    # (what's also required for testing here)
    import EcologicalNetworksDynamics.Tests:
        EN, F, T, @test_err, @fails, @genfailsmacro, @jl_deffails, @propfails, @callfails,
        addfails
    using Test

    const V = Value
    const S = System{Value}

    @testset "Basic components/methods/properties." begin

        # Build empty system.
        s = S()

        # Add component.
        add!(s, NLines(3))

        # Call method.
        @test get_n(s) == 3

        # Read property (equivalent to the above).
        @test s.n == 3

        # Forbid unexistent properties.
        @propfails(s.x, S, :x, "Unknown property.")
        @test_err(s.x, "In property `.x` of `$System{$Value}`: Unknown property.\n")
        # Forbid existent properties without appropriate component.
        @propfails(s.b, S, :b, "Component $_B is required to read this property.")
        # Same with methods.
        @jl_deffails(get_x(s), :get_x, Basics)
        @callfails(get_b(s), V, :get_b, "Requires component $_B.")
        @test_err(get_b(s), "In method `get_b` for `$Value`: Requires component $_B.\n")

        # Forbid write.
        @propfails((s.n = 4), S, :n, "This property is read-only.")

        # Cannot add component twice.
        addfails.@broughtalready(add!(s, NLines(5)), _Size, [NLines])
        @test_err(add!(s, NLines(5)),
            """
            Blueprint would expand into component $_Size, \
            which is already in the system.
            in $NLines
            """)

        # Add component requiring previous one from a blueprint.
        t = s + A.Uniform(5)
        @test t.a == [5, 5, 5]

        # Fail if custom blueprint constraints are not enforced.
        addfails.@check(
            s + A.Raw([5, 5]),
            [A.Raw],
            "Cannot expand 2 'a' values into 3 lines.",
            true,
        )
        @test_err(
            s + A.Raw([5, 5]),
            """
            Blueprint cannot expand against current system value:
            Cannot expand 2 'a' values into 3 lines.
            Not all blueprints have been expanded.
            This means that the system consistency is still guaranteed, \
            but some components have not been added.
            in $(A.Raw)
            """
        )

        # Cannot add component if requirement is missing.
        e = System{Value}() # Empty.
        addfails.@missingrequired(
            e + B.Raw([8, 8, 8]), # Size is brought, but not A.
            _A, _B, [B.Raw], nothing,
        )
        @test_err(
            e + B.Raw([8, 8, 8]),
            """
            Component $_B requires $_A, \
            neither found in the system nor brought by the blueprints.
            in $(B.Raw)
            """
        )

        # Chain summations.
        s = e + NLines(3) + A.Uniform(5) + B.Uniform(8)

        # Use method/property that requires several components.
        @test s.sum == [13, 13, 13]

        # Cannot add incompatible component.
        addfails.@sysconflict(
            s + SparseMark(),
            _Sparse, nothing, [SparseMark], _Size, nothing, nothing,
        )
        @test_err(s + SparseMark(),
            """
            Blueprint would expand into $_Sparse, \
            which conflicts with $_Size already in the system.
            in $SparseMark
            """
        )

        # Blueprint checking may depend on other components.
        r = ReflectionMark()
        s = e + NLines(5)
        addfails.@check(s + r, [ReflectionMark], "Cannot reflect from no data.", true)

        # Blueprint expansion may depend on other components.
        sa = s + A.Uniform(5)
        sb = sa + B.Uniform(8)
        sa += r # Same blueprint..
        sb += r # .. different expansion.
        @test sa.reflection == collect("AAAAA")
        @test sb.reflection == collect("ABABA")

        # Read from aliased properties.
        @test sa.ref == sa.reflection

        # Modify from aliased properties.
        sa.ref = "UVW" # (cycling semantics)
        @test sa.ref == collect("UVWUV")

        # Blueprint expansion may require other components
        # without its component itself requiring them.
        addfails.@missingrequired(
            s + ReflectFromB(), # .. although reflection does not require B in general.
            _A, nothing, [ReflectFromB], nothing,
        )
        sa = s + A.Raw([1, 2, 3, 2, 1])
        sr = sa + ReflectFromB()
        @test sr.reflection == collect("12321")

        #-----------------------------------------------------------------------------------
        # List properties.

        # All possible system properties and their dependencies.
        props = F.properties(typeof(sa))
        @test sort(map(((n, r, w, g),) -> (n, r, w, F.singleton_instance.(g)), props)) == [
            (:a, get_a, nothing, Component[A]),
            (:b, get_b, nothing, Component[B]),
            (:n, get_n, nothing, Component[Size]),
            (:ref, get_reflection, set_reflection!, Component[Reflection]),
            (:reflection, get_reflection, set_reflection!, Component[Reflection]),
            (:sum, get_sum, nothing, Component[A, B]),
        ]

        # Only the ones available on this instance.
        props = F.properties(sa)
        @test sort(collect(props)) == [(:a, get_a, nothing), (:n, get_n, nothing)]

        # Only the ones *missing* on this instance.
        props = F.latent_properties(sa)
        @test sort(map(((n, r, w, g),) -> (n, r, w, F.singleton_instance.(g)), props)) == [
            (:b, get_b, nothing, Component[B]),
            (:ref, get_reflection, set_reflection!, Component[Reflection]),
            (:reflection, get_reflection, set_reflection!, Component[Reflection]),
            (:sum, get_sum, nothing, Component[B]),
        ]

    end

    # ======================================================================================
    @testset "Blueprints imply each other." begin

        e = System{Value}() # Empty.

        # Implying NLines from A.Raw for Size..
        a = A.Raw([5, 5])
        s = e + a
        @test has_component(s, Size)
        @test has_component(s, A)
        @test s.n == 2

        # Display path to failing brought sub-blueprint in case of failure.
        addfails.@check(
            e + A.Raw([]),
            [NLines, A.Raw],
            "Not a positive number of lines: 0.",
            false,
        )
        @test_err(e + A.Raw([]),
            """
            Blueprint value cannot be expanded:
            Not a positive number of lines: 0.
            in $NLines
             implied by: $(A.Raw)
            """
        )

        # Implied blueprint are not expanded if their component is already there.
        s = e + NLines(2)
        s += a # No error.
        @test s.a == [5, 5]

        # But a failure to match is still a failure.
        s = e + NLines(3)
        addfails.@check(
            s += a,
            [A.Raw],
            "Cannot expand 2 'a' values into 3 lines.",
            true,
        )

    end

    @testset "Guard end users agains components library bugs." begin
        #-----------------------------------------------------------------------------------
        # Guard end users against components library bugs.

        struct Llz_b <: Blueprint{Value} end
        define_blueprint(Llz_b)
        F.lower(_, ::Llz_b, _) = throw("bug")
        define_component(:Llz, Value, Basics; blueprints = [:Llz => Llz_b])

        addfails.@lower(S(Llz_b()), [Llz_b])
        @test_err(S(Llz_b()),
            """
            Unexpected failure during data lowering.
            This is a bug in the component library. \
            Please report to component authors if you can reproduce with a minimal example.
            Not all blueprints have been expanded.
            This means that the system consistency is still guaranteed, \
            but some components have not been added.
            in $Llz_b
            """)

        struct Sta_b <: Blueprint{Value} end
        define_blueprint(Sta_b)
        F.expand!(_, ::Sta_b, _) = throw("bug")
        define_component(:Sta, Value, Basics; blueprints = [:Sta => Sta_b])
        T.@errfails(S(Sta_b()),
            """\n\
            ⚠ ⚠ ⚠ Failure during blueprint expansion. ⚠ ⚠ ⚠
            This is a bug in the components library.
            This system state consistency is no longer guaranteed by the program.
            Consider reporting to component authors \
            if you can reproduce with a minimal example.
            In any case, please drop the current system value and create a new one.
            in $Sta_b
            """)

    end

    # ======================================================================================
    @testset "Clone/fork the system by copying it any time." begin

        init = System{Value}()
        s = copy(init)
        @test collect(F.components(s)) == []
        @test collect(F.properties(s)) == []

        # Check that the original system is always empty.
        function test_empty(i)
            @test isempty(collect(F.components(i)))
            @callfails(get_a(i), V, :get_a, "Requires component $_A.")
            @propfails(i.a, S, :a, "Component $_A is required to read this property.")
        end
        test_empty(init)

        add!(s, NLines(3), A.Uniform(5))
        @test s.a == [5, 5, 5]
        test_empty(init)

        add!(s, B.Uniform(8), ReflectionMark())
        @test s.b == [8, 8, 8]
        @test s.ref == collect("ABA")
        test_empty(init)

        # Use the + operator to add components without altering the original system.
        a = A.Raw([5, 8, 9])
        s = init + a
        @test s.a == [5, 8, 9]
        test_empty(init)

        # Blueprints must never leak references into the inner system.
        a.a[1] *= 10
        t = init + a
        @test t.a == [50, 8, 9] # Different expansion result in new system.
        @test s.a == [5, 8, 9] # Original system unchanged.
        test_empty(init)

    end

end
end

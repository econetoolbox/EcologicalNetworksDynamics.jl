module Methods

using EcologicalNetworksDynamics.Framework: F

# The plain value to wrap in a "system" in subsequent tests.
# Every test module has its own one,
# otherwise properties would propagate from one module to the next.
macro genvalue()
    quote
        mutable struct Value
            _member::Union{Nothing,Int64}
            Value() = new(nothing)
        end
        Base.copy(v::Value) = deepcopy(v)
        # Willing to enjoy wrapped value properties.
        Base.getproperty(v::Value, p::Symbol) = $F.unchecked_getproperty(v, p)
        Base.setproperty!(v::Value, p::Symbol, rhs) =
            $F.unchecked_setproperty!(v, p, rhs)
        # Convenience default for this test module.
        define_method(fn, V = Value; kwargs...) = $F.define_method(fn, V; kwargs...)
        const V = Value
        const S = $F.System{Value}
    end |> esc
end

# ==========================================================================================
module Calls

    using ..Methods: @genvalue
    @genvalue
    local Value, V, S # (reassure JuliaLS)

    using EcologicalNetworksDynamics.Framework:
        F, Blueprint, Component, System, define_blueprint

    using EcologicalNetworksDynamics.Tests:
        @jl_callfails, addfails, @methfails, @callfails, @propfails
    using Test

    define_component(name, V = Value; kwargs...) =
        F.define_component(name, V, Calls; kwargs...)

    @testset "Calls to `define_method()`." begin

        # ==================================================================================
        # Typical regular use.

        # One component that all subsequent tested methods depend on.
        struct Unf_b <: Blueprint{Value} end
        define_blueprint(Unf_b)
        define_component(:Unf; blueprints = [:b => Unf_b])
        F.expand!(s, ::Unf_b) = (F.value(s)._member = 0)
        s = System{Value}(Unf.b())

        # Simple valid invocation.
        eval(quote
            get_m(v::Value) = v._member
            set_m!(v::Value, m) = (v._member = m)
        end)
        define_method(get_m; read_as = [:m], depends = [Unf])
        define_method(set_m!; write_as = [:m], depends = [Unf])

        # Read/write like property.
        @test get_m(s) == 0
        @test s.m == 0
        set_m!(s, 5)
        @test get_m(s) == s.m == 5
        s.m = 8
        @test get_m(s) == s.m == 8

        # Checked method issue correct errors when the required components are missing.
        e = System{Value}()
        @callfails(get_m(e), V, :get_m, "Requires component $_Unf.")
        @callfails(set_m!(e, 0), V, :set_m!, "Requires component $_Unf.")
        @propfails(e.m, S, :m, "Component $_Unf is required to read this property.")
        @propfails((e.m = 0),
            S, :m, "Component $_Unf is required to write to this property.")

        # ==================================================================================
        # Variations.

        # Explicit empty lists.
        eval(quote
            ikw(v::Value) = v.m
        end)
        define_method(ikw; read_as = [], depends = [])
        @test ikw(s) == 8

        # Forgot to specify value type.
        eval(quote
            dti(v::Value) = v.m
        end)
        @methfails(
            define_method(dti, nothing; read_as = [:dti]),
            dti,
            "The system value type cannot be inferred when no dependencies are given.\n\
             Consider making it explicit with the first macro argument: `$dti{MyValueType}`."
        )

        # Forgot to specify a receiver.
        eval(quote
            kck(v) = v.m
        end)
        @methfails(
            define_method(kck; read_as = [:kck]),
            kck,
            "No suitable method has been found to mark $kck as a system method. \
             Valid methods must have at least one 'receiver' argument of type ::$Value."
        )

        # Only methods with the right receivers are wrapped.
        eval(quote
            enm(a::Int, b::Int) = a - b
            enm(a, v::Value, b) = v.m * (a - b)
            enm(a, b, v::Value; shift = 0) = (a - b) / v.m + shift # Support kwargs.
        end)
        define_method(enm; depends = [Unf])
        @test enm(10, 4) == 6 # As-is.
        @test enm(10, s, 4) == 8 * 6 # Overriden for the system.
        @test enm(10, 4, s) == 6 / 8
        @test enm(10, 4, s; shift = 5) == 6 / 8 + 5
        @jl_callfails(enm(s, 4), enm, (s, 4)) # Not overriden.
        # Checked on their receiver arguments.
        @callfails(enm(10, 4, e), V, :enm, "Requires component $_Unf.")

        # Forbid several receivers (yet).
        eval(quote
            ara(a, v::Value, b, w::Value) = v.m * (a - b) / w.m
        end)
        @methfails(
            define_method(ara; depends = [Unf]),
            ara,
            "Receiving several (possibly different) system/values parameters \
             is not yet supported by the framework. \
             Here both parameters :w and :v are of type $Value."
        )

        # Allow unused receiver.
        eval(quote
            pum(a, ::Value) = a + 1
        end)
        define_method(pum; depends = [Unf])
        @test pum(4, s) == 5 # Method generated for system.
        # Receiver actually *used* in the generated method.
        @callfails(pum(4, e), V, :pum, "Requires component $_Unf.")

        # System hook.
        eval(quote
            received_hook = []
            function hyy(a::Int, v::Value, _s::System)
                empty!(received_hook)
                push!(received_hook, _s)
                a + v.m
            end
        end)
        define_method(hyy; depends = [Unf])
        @test hyy(5, s) == 5 + 8 # Can be called without the hook.
        @test length(received_hook) == 1
        @test first(received_hook) === s # But it has been used transfered.

        # Cannot ask for several hooks.
        eval(quote
            zmz(a::Int, s::System, v::Value, ::System) = a + v.m - whatever(s)
        end)
        @methfails(
            define_method(zmz; depends = [Unf]),
            zmz,
            "Receiving several (possibly different) system hooks \
             is not yet supported by the framework. \
             Here both parameters :s and :#4 are of type $System."
        )

        #-----------------------------------------------------------------------------------
        # Basic input checks.

        eval(quote
            oab(v::Value) = v.m
        end)
        @methfails(
            define_method(oab; read_as = [4 + 5]),
            oab,
            "Property name [1] is not a simple identifier path: 9 ::$Int"
        )

        @methfails(
            define_method(oab; read_as = [:oab], depends = [4 + 5]),
            oab,
            "Method dependency [1]:\nNot a component: 9 ::$Int"
        )

        @methfails(
            define_method(oab; read_as = [:oab], depends = [Unf, 4 + 5]),
            oab,
            "Method dependency [2]:\nNot a component: 9 ::$Int"
        )

        @methfails(
            define_method(oab; read_as = [:oab], write_as = [:oab]),
            oab,
            "Cannot specify both `read_as` and `write_as` sections."
        )

        #-----------------------------------------------------------------------------------
        # Depends section.

        # Inconsistent system values.
        struct Rle_b <: Blueprint{Int} end
        define_blueprint(Rle_b)
        define_component(:Rle, Int; blueprints = [:b => Rle_b])
        eval(quote
            hjc(v::Value) = v.m
        end)
        @methfails(
            define_method(hjc; depends = [Unf, Rle]),
            hjc,
            "Depends section: system value type is supposed to be `$Value`, \
             but $_Rle subtypes `$Component{$Int}` and not `$Component{$Value}`.",
        )

        @methfails(
            define_method(hjc, Int; depends = [Unf]),
            hjc,
            "Depends section: system value type is supposed to be `$Int`, \
             but $_Unf subtypes `$Component{$Value}` and not `$Component{$Int}`.",
        )

        # Dependency not recorded as a method.
        eval(quote
            dbm(v::Int) = v
        end)
        @methfails(
            define_method(hjc; depends = [dbm]),
            hjc,
            "Method dependency [1]:\n\
             The function specified as a dependency \
             has not been recorded as a system method: $Calls.dbm ::$(typeof(dbm))"
        )

        # Dependency not recorded as a method for this system value.
        eval(quote
            exu(v::Int) = v
        end)
        define_method(exu, Int)
        @methfails(
            define_method(hjc; depends = [exu]),
            hjc,
            "Depends section: system value type is supposed to be `$Value`, \
             but `$exu` has not been recorded as a system method for this type."
        )

        # Ambiguous dependency.
        eval(quote
            luu(i::Int) = i
            luu(v::Value) = v.m
        end)
        define_method(luu, Int)
        define_method(luu, Value; depends = [Unf])
        eval(quote
            txc(v::Value) = v.m + 1
        end)
        @methfails(
            define_method(txc, nothing; depends = [luu]),
            txc,
            "First dependency: the function specified has been recorded \
             as a method for [$Int, $Value]. \
             It is ambiguous which one the focal method is being defined for."
        )
        # Disambiguate.
        define_method(txc, Value; depends = [luu])
        @test txc(s) == 8 + 1
        @callfails(txc(e), V, :txc, "Requires component <$Unf>.") # Correctly inherited.

        #-----------------------------------------------------------------------------------
        # Properties.

        eval(quote
            kqo(v::Value, b) = b + v.m
        end)
        @methfails(
            define_method(kqo; depends = [Unf], read_as = [:kqo]),
            kqo,
            "The function cannot be called \
             with exactly 1 argument of type `$Value` \
             as required to be set as a 'read' property.",
        )

        eval(quote
            vho(v::Value) = v.m
            vho!(v::Value, a, b) = v.m + a + b
        end)
        define_method(vho; depends = [Unf], read_as = [:vho])
        @methfails(
            define_method(vho!; depends = [Unf], write_as = [:vho]),
            vho!,
            "The function cannot be called \
             with exactly 2 arguments, the first one being of type `$Value`, \
             as required to be set as a 'write' property.",
        )

        # Disallow write-only properties.
        eval(quote
            tlc(v::Value, rhs) = (v.m = rhs)
        end)
        @methfails(
            define_method(tlc; depends = [Unf], write_as = [:tlc]),
            tlc,
            "The property :tlc cannot be marked 'write' \
             without having first been marked 'read' for target `$System{$Value}`.",
        )

        # Guard against properties overrides.
        # (read)
        eval(quote
            vnq(v::Value) = v.m
        end)
        define_method(vnq; depends = [Unf], read_as = [:vnq])
        eval(quote
            fhh(v::Value) = v.m
        end)
        @methfails(
            define_method(fhh; depends = [Unf], read_as = [:vnq]),
            fhh,
            "The property :vnq is already defined for target `$System{$Value}`."
        )

        # (write)
        eval(quote
            phs(v::Value) = v.m
            cll(v::Value) = v.m
            phs!(v::Value, rhs) = (v.m = rhs)
            cll!(v::Value, rhs) = (v.m = rhs)
        end)
        define_method(phs; depends = [Unf], read_as = [:phs])
        define_method(phs!; depends = [Unf], write_as = [:phs])
        define_method(cll; depends = [Unf], read_as = [:cll])
        @methfails(
            define_method(cll!; depends = [Unf], write_as = [:phs]),
            cll!,
            "The property :phs is already marked 'write' for target `$System{$Value}`.",
        )

        #-----------------------------------------------------------------------------------
        # Guard against double specifications.
        eval(quote
            yqp(v::Value) = v.m
        end)
        define_method(yqp; depends = [Unf], read_as = [:yqp])
        @methfails(
            define_method(yqp; depends = [Unf]),
            yqp,
            "Function `$yqp` already marked as a method for systems of `$Value`."
        )

    end
end

# ==========================================================================================
module Abstracts

    using ..Methods: @genvalue
    @genvalue
    local Value, V, S # (reassure JuliaLS)

    using EcologicalNetworksDynamics.Framework:
        F, Blueprint, System, Component, define_blueprint, add!

    using EcologicalNetworksDynamics.Tests: @methfails, @callfails, @propfails
    using Test

    define_component(name, V = Value; kwargs...) =
        F.define_component(name, V, Abstracts; kwargs...)

    @testset "Abstract component semantics for methods." begin

        # Component type hierachy.
        #
        #      A
        #    ┌─┼─┐
        #    B C D
        #
        abstract type A <: Component{Value} end
        struct B_b <: Blueprint{Value} end
        struct C_b <: Blueprint{Value} end
        struct D_b <: Blueprint{Value} end
        define_blueprint(B_b)
        define_blueprint(C_b)
        define_blueprint(D_b)
        define_component(:B; super = A, blueprints = [:b => B_b])
        define_component(:C; super = A, blueprints = [:b => C_b])
        define_component(:D; super = A, blueprints = [:b => D_b])

        eval(quote
            f(v::Value, x) = x + v._member
            get_prop(v::Value) = v._member
            set_prop!(v::Value, x) = (v._member = x)
        end)
        define_method(f; depends = [A])
        define_method(get_prop; depends = [A], read_as = [:prop])
        define_method(set_prop!; depends = [A], write_as = [:prop])

        s = System{Value}()
        @callfails(f(s, 5), V, :f, "Requires a component $A.")
        @propfails(s.prop,
            S, :prop, "A component $A is required to read this property.")
        @propfails((s.prop = 5),
            S, :prop, "A component $A is required to write to this property.")

        # Any subtype enables the method and properties.
        add!(s, B.b())
        set_prop!(s, 1)
        @test f(s, 5) == 6
        @test s.prop == 1
        s.prop = 5
        @test s.prop == 5

        # Inheriting redundant dependencies from various methods is ok.
        eval(quote
            tai(v::Value) = v.m
            trt(v::Value) = v.m
            rrk(v::Value) = v.m
            dgw(v::Value) = v.m
        end)
        define_method(tai; depends = [B]) # Concrete.
        define_method(trt; depends = [A]) # Abstract.
        define_method(rrk; depends = [tai, trt])
        define_method(dgw; depends = [trt, tai]) # Order does not matter.
        @test collect(F.depends(System{Value}, rrk)) == [A] # Only.
        @test collect(F.depends(System{Value}, dgw)) == [A] # Only.

    end
end

# ==========================================================================================
module PropertySpaces

    using ..Methods: @genvalue
    @genvalue
    local Value, V, S # (reassure JuliaLS)

    using EcologicalNetworksDynamics.Framework:
        F, Blueprint, System, define_blueprint, @PropertySpace

    using EcologicalNetworksDynamics.Tests: T, @methfails, @callfails, @propfails
    using Test

    define_component(name, V = Value; kwargs...) =
        F.define_component(name, V, PropertySpaces; kwargs...)

    @testset "Property spaces." begin

        function are_props(s, expected)
            actual = sort(first.(F.properties(s)))
            actual == expected && return true
            T.showcompare(stderr, expected, actual)
            false
        end

        s = System{Value}()

        @test are_props(s, [])

        # Util to define property subspace.
        @test @PropertySpace(a.b.c, Value) ===
              F.PropertySpace{:c,
            F.PropertySpace{:b,F.PropertySpace{:a,System{Value},Value},Value},Value}

        # Create a property space, accessible itself via a root property.
        MRE = @PropertySpace(mre, Value)
        eval(quote
            get_mre(::Value, s::System) = $MRE(s)
        end)
        define_method(get_mre; read_as = [:mre])

        # Property appeared on the list.
        @test are_props(System{Value}, [:mre])
        @test are_props(s, [:mre]) # But this instance still has nothing.

        # Obtain the space.
        @test s.mre isa MRE
        @propfails((s.mre = 5), S, :mre, "This property is read-only.")

        # The space is still empty.
        @propfails(s.mre.a, MRE, :a, "Unknown property.")
        T.@test_err(s.mre.a, "In property `mre.a` of `$S`: Unknown property.\n")

        # Add property to the space.
        eval(quote
            get_htl(::Value) = "htl"
        end)
        define_method(get_htl; read_as = [:(mre.htl)])

        # Check it out.
        @test are_props(@PropertySpace(mre, Value), [:htl])
        @test are_props(s.mre, [:htl])

        # Access the property.
        @test s.mre.htl == "htl"
        mre = s.mre # Delayed access.
        @test mre.htl == "htl"
        @propfails((mre.htl = 5), MRE, :htl, "This property is read-only.")

        # Inaccessible at the root level.
        @propfails(s.htl, S, :htl, "Unknown property.")

        # Add subspace as yet another property.
        TXV = @PropertySpace(mre.txv, Value)
        eval(quote
            get_txv(::Value, s::System) = $TXV(s)
        end)
        define_method(get_txv; read_as = [:(mre.txv)])
        @test s.mre.txv isa TXV

        # Add property to the subspace.
        eval(quote
            get_dru(::Value) = "dru"
        end)
        define_method(get_dru; read_as = [:(mre.txv.dru)])
        T.@test_err(s.mre.txv.a, "In property `mre.txv.a` of `$S`: Unknown property.\n")
        @propfails(s.mre.txv.a, TXV, :a, "Unknown property.")
        @propfails(s.mre.dru, MRE, :dru, "Unknown property.")
        @propfails(s.dru, S, :dru, "Unknown property.")
        @test s.mre.txv.dru == "dru"

        # Property spaces can also require components to be read.
        struct Anq_b <: Blueprint{Value} end
        define_blueprint(Anq_b)
        define_component(:Anq; blueprints = [:b => Anq_b])
        GOA = @PropertySpace(goa, Value)
        GYQ = @PropertySpace(goa.gyq, Value)
        eval(quote
            get_goa(::Value, s::System) = $GOA(s)
            get_gyq(::Value, s::System) = $GYQ(s)
        end)
        define_method(get_goa; read_as = [:goa])
        define_method(get_gyq; depends = [Anq], read_as = [:(goa.gyq)])

        # Both type/instance yield same results..
        @test are_props(System{Value}, [:goa, :mre])
        @test are_props(s, [:goa, :mre])
        # .. unless the instance misses dependencies.
        @test are_props(GOA, [:gyq])
        @test are_props(s.goa, [])

        @propfails(s.goa.gyq,
            GOA, :gyq, "Component $_Anq is required to read this property.")
        goa = s.goa # Delayed access, same result.
        @propfails(goa.gyq,
            GOA, :gyq, "Component $_Anq is required to read this property.")
        s += Anq.b()
        @test s.goa.gyq isa GYQ

        # Writable accesses.
        eval(quote
            set_htl!(v::Value, rhs) = (v._member = rhs)
        end)

        @methfails(
            define_method(set_htl!; write_as = [:htl]),
            set_htl!,
            "The property :htl cannot be marked 'write' \
             without having first been marked 'read' for target `$System{$Value}`."
        )

        @methfails(
            define_method(set_htl!; write_as = [:(mre.a)]),
            set_htl!,
            "The property :(mre.a) cannot be marked 'write' \
             without having first been marked 'read' \
             for target `$(F.PropertySpace){<.mre>, $Value}`."
        )

        # Finally succeed.
        define_method(set_htl!; write_as = [:(mre.htl)])

        @test isnothing(F.value(s)._member)
        s.mre.htl = 5
        @test F.value(s)._member == 5
        mre = s.mre # Delayed access.
        mre.htl = 8
        @test F.value(s)._member == 8

        # Dependent write.
        struct Vnq_b <: Blueprint{Value} end
        define_blueprint(Vnq_b)
        define_component(:Vnq; blueprints = [:b => Vnq_b])
        eval(quote
            get_nbu(v::Value) = v._member
            set_nbu!(v::Value, rhs) = (v._member = rhs + 1)
        end)
        define_method(get_nbu; read_as = [:(goa.gyq.nbu)])
        define_method(set_nbu!; depends = [Vnq], write_as = [:(goa.gyq.nbu)])

        @test s.goa.gyq.nbu == 8
        @propfails((s.goa.gyq.nbu = 9),
            GYQ, :nbu, "Component $_Vnq is required to write to this property.")
        s += Vnq.b()
        s.goa.gyq.nbu = 9
        @test s.goa.gyq.nbu == 10
        gyq = s.goa.gyq # Delayed access.
        gyq.nbu = 19
        @test gyq.nbu == s.goa.gyq.nbu == 20

        # Mixed levels aliased properties.
        eval(quote
            get_orw(::Value) = "orw"
        end)
        define_method(get_orw; read_as = [:orw, :(goa.orw), :(goa.gyq.orw)])
        @test s.orw == s.goa.orw == s.goa.gyq.orw == "orw"

        # Same dependencies for all aliases.
        s = System{Value}(Anq.b())
        eval(quote
            get_btt(::Value) = "btt"
        end)
        define_method(
            get_btt;
            depends = [Vnq],
            read_as = [:btt, :(goa.btt), :(goa.gyq.btt)],
        )

        @propfails(s.btt, S, :btt, "Component $_Vnq is required to read this property.")
        @propfails(s.goa.btt,
            GOA, :btt, "Component $_Vnq is required to read this property.")
        @propfails(s.goa.gyq.btt,
            GYQ, :btt, "Component $_Vnq is required to read this property.")
        s += Vnq.b()
        @test s.btt == s.goa.btt == s.goa.gyq.btt == "btt"

        # Dependent write aliases.
        struct Tkq_b <: Blueprint{Value} end
        define_blueprint(Tkq_b)
        define_component(:Tkq; blueprints = [:b => Tkq_b])
        eval(quote
            set_btt!(v::Value, rhs) = (v._member = 10 * rhs)
        end)
        define_method(
            set_btt!;
            depends = [Tkq],
            write_as = [:btt, :(goa.btt), :(goa.gyq.btt)],
        )

        @propfails((s.btt = 44),
            S, :btt, "Component $_Tkq is required to write to this property.")
        @propfails((s.goa.btt = 44),
            GOA, :btt, "Component $_Tkq is required to write to this property.")
        @propfails((s.goa.gyq.btt = 44),
            GYQ, :btt, "Component $_Tkq is required to write to this property.")
        s += Tkq.b()
        s.btt = 44
        @test F.value(s)._member == 440
        s.goa.btt = 55
        @test F.value(s)._member == 550
        s.goa.gyq.btt = 66
        @test F.value(s)._member == 660

    end

end

end

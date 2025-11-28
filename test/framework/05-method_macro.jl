module MethodMacro

using EcologicalNetworksDynamics.Framework

# Use submodules to not clash component names.
# ==========================================================================================
module Invocations
using ..MethodMacro
using EcologicalNetworksDynamics.Framework
using Main: @failswith, @sysfails, @methfails
using Test

# The plain value to wrap in a "system" in subsequent tests.
mutable struct Value
    _member::Union{Nothing,Int64}
    Value() = new(nothing)
end
Base.copy(v::Value) = deepcopy(v)
# Willing to enjoy wrapped value properties.
Base.getproperty(v::Value, p::Symbol) = Framework.unchecked_getproperty(v, p)
Base.setproperty!(v::Value, p::Symbol, rhs) = Framework.unchecked_setproperty!(v, p, rhs)
export Value

@testset "Invocation variations for @method macro." begin

    # ======================================================================================
    # Typical regular use.

    # One component that all subsequent tested methods depend on.
    struct Unf_b <: Blueprint{Value} end
    @blueprint Unf_b
    @component Unf{Value} blueprints(b::Unf_b)
    Framework.expand!(v, ::Unf_b) = (v._member = 0)
    s = System{Value}(Unf.b())

    # Simple valid invocation.
    eval(quote
        get_m(v::Value) = v._member
        set_m!(v::Value, m) = (v._member = m)
    end)
    @method get_m read_as(m) depends(Unf)
    @method set_m! write_as(m) depends(Unf)

    # Read/write like property.
    @test get_m(s) == 0
    @test s.m == 0
    set_m!(s, 5)
    @test get_m(s) == s.m == 5
    s.m = 8
    @test get_m(s) == s.m == 8

    # Checked method issue correct errors when the required components are missing.
    e = System{Value}()
    @sysfails(get_m(e), Method(get_m, "Requires component $_Unf."))
    @sysfails(set_m!(e, 0), Method(set_m!, "Requires component $_Unf."))
    @sysfails(e.m, Property(m, "Component $_Unf is required to read this property."))
    @sysfails(
        (e.m = 0),
        Property(m, "Component $_Unf is required to write to this property.")
    )

    # ======================================================================================
    # Variations.

    # Block-syntax.
    eval(quote
        aoy(v::Value) = v.m
    end)
    @method begin
        aoy
        read_as(aoy)
        depends(Unf)
    end
    @test aoy(s) == 8

    # Explicit value type without dependencies.
    eval(quote
        cna(v::Value) = v.m
    end)
    @method cna{Value} read_as(cna)
    @test cna(s) == 8

    # Explicit empty lists.
    eval(quote
        ikw(v::Value) = v.m
    end)
    @method ikw{Value} read_as() depends()
    @test ikw(s) == 8

    # Forgot to specify value type in the @method call.
    eval(quote
        dti(v::Value) = v.m
    end)
    @methfails(
        (@method dti read_as(dti)),
        dti,
        "The system value type cannot be inferred when no dependencies are given.\n\
         Consider making it explicit with the first macro argument: `$dti{MyValueType}`."
    )

    # Forgot to specify a receiver.
    eval(quote
        kck(v) = v.m
    end)
    @methfails(
        (@method kck{Value} read_as(kck)),
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
    @method enm depends(Unf)
    @test enm(10, 4) == 6 # As-is.
    @test enm(10, s, 4) == 8 * 6 # Overriden for the system.
    @test enm(10, 4, s) == 6 / 8
    @test enm(10, 4, s; shift = 5) == 6 / 8 + 5
    @failswith(enm(s, 4), MethodError) # Not overriden.
    # Checked on their receiver arguments.
    @sysfails(enm(10, 4, e), Method(enm, "Requires component $_Unf."))

    # Forbid several receivers (yet).
    eval(quote
        ara(a, v::Value, b, w::Value) = v.m * (a - b) / w.m
    end)
    @methfails(
        (@method ara depends(Unf)),
        ara,
        "Receiving several (possibly different) system/values parameters \
         is not yet supported by the framework. \
         Here both parameters :w and :v are of type $Value."
    )

    # Allow unused receiver.
    eval(quote
        pum(a, ::Value) = a + 1
    end)
    @method pum depends(Unf)
    @test pum(4, s) == 5 # Method generated for system.
    # Receiver actually *used* in the generated method.
    @sysfails(pum(4, e), Method(pum, "Requires component $_Unf."))

    # System hook.
    eval(quote
        received_hook = []
        function hyy(a::Int, v::Value, _s::System)
            empty!(received_hook)
            push!(received_hook, _s)
            a + v.m
        end
    end)
    @method hyy depends(Unf)
    @test hyy(5, s) == 5 + 8 # Can be called without the hook.
    @test length(received_hook) == 1
    @test first(received_hook) === s # But it has been used transfered.

    # Cannot ask for several hooks.
    eval(quote
        zmz(a::Int, s::System, v::Value, ::System) = a + v.m - whatever(s)
    end)
    @methfails(
        (@method zmz depends(Unf)),
        zmz,
        "Receiving several (possibly different) system hooks \
         is not yet supported by the framework. \
         Here both parameters :s and :#4 are of type $System."
    )

    #---------------------------------------------------------------------------------------
    # Basic input checks.

    # Macro input evaluation.
    eval(quote
        oab(v::Value) = v.m
        comp_xp() = Unf
        value_xp() = Value
    end)
    @method oab{value_xp()} read_as(oab) depends(comp_xp())
    @test oab(s) == 8
    @sysfails(oab(e), Method(oab, "Requires component $_Unf."))

    @methfails((@method()), nothing, ["Not enough macro input provided. Example usage:\n"],)

    @methfails(
        (@method 5 + 8),
        nothing,
        "System method: expression does not evaluate to a 'Function':\n\
         Expression: :(5 + 8)\n\
         Result: 13 ::$Int"
    )

    @methfails(
        (@method oab{Undef}),
        nothing,
        "System value type: expression does not evaluate: :Undef. \
         (See error further down the exception stack.)"
    )

    @methfails(
        (@method oab{4 + 5}),
        nothing,
        "System value type: expression does not evaluate to a 'Type':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @methfails(
        (@method oab{Value} 4 + 5),
        oab,
        "Unexpected @method section. \
         Expected `depends(..)`, `read_as(..)` or `write_as(..)`. \
         Got instead: :(4 + 5)."
    )

    @methfails(
        (@method oab{Value} notasection(oab)),
        oab,
        "Invalid section keyword: :notasection. \
         Expected :read_as or :write_as or :depends."
    )

    @methfails(
        (@method oab{Value} read_as(4 + 5)),
        oab,
        "Property name is not a simple identifier path: :(4 + 5)."
    )

    @methfails(
        (@method oab{Value} read_as(oab) depends(4 + 5)),
        oab,
        "First dependency: expression does not evaluate to a component:\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @methfails(
        (@method oab{Value} read_as(oab) depends(Unf, 4 + 5)),
        oab,
        "Depends section: expression does not evaluate to a component for '$Value':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @methfails(
        (@method oab{Value} read_as(oab) write_as(oab)),
        oab,
        "Cannot specify both :read_as section and :write_as."
    )

    #---------------------------------------------------------------------------------------
    # Depends section.

    # Inconsistent system values.
    struct Rle_b <: Blueprint{Int} end
    @blueprint Rle_b
    @component Rle{Int} blueprints(b::Rle_b)
    eval(quote
        hjc(v::Value) = v.m
    end)
    @methfails(
        (@method hjc depends(Unf, Rle)),
        hjc,
        "Depends section: expression does not evaluate \
         to a component for '$Value', but for '$Int':\n\
         Expression: :Rle\n\
         Result: $Rle ::<$Rle>",
    )

    @methfails(
        (@method hjc{Int} depends(Unf)),
        hjc,
        "Depends section: system value type is supposed to be '$Int' \
         based on the first macro argument, \
         but $_Unf subtypes '$Component{$Value}' and not '$Component{$Int}'.",
    )

    # Dependency not recorded as a method.
    eval(quote
        dbm(v::Int) = v
    end)
    @methfails(
        (@method hjc depends(dbm)),
        hjc,
        "First dependency: the function specified as a dependency \
         has not been recorded as a system method:\n\
         Expression: :dbm\n\
         Result: dbm ::$(typeof(dbm))"
    )

    # Dependency not recorded as a method for this system value.
    eval(quote
        exu(v::Int) = v
    end)
    @method exu{Int}
    @methfails(
        (@method hjc{Value} depends(exu)),
        hjc,
        "Depends section: system value type is supposed to be '$Value' \
         based on the first macro argument, \
         but '$exu' has not been recorded as a system method for this type."
    )

    # Ambiguous dependency.
    eval(quote
        luu(i::Int) = i
        luu(v::Value) = v.m
    end)
    @method luu{Int}
    @method luu{Value} depends(Unf)
    eval(quote
        txc(v::Value) = v.m + 1
    end)
    @methfails(
        (@method txc depends(luu)),
        txc,
        "First dependency: the function specified has been recorded \
         as a method for [$Int, $Value]. \
         It is ambiguous which one the focal method is being defined for."
    )

    # Disambiguate.
    @method txc{Value} depends(luu)
    @test txc(s) == 8 + 1
    @sysfails(txc(e), Method(txc, "Requires component <$Unf>.")) # Correctly inherited.

    #---------------------------------------------------------------------------------------
    # Properties.

    eval(quote
        kqo(v::Value, b) = b + v.m
    end)
    @methfails(
        (@method kqo depends(Unf) read_as(kqo)),
        kqo,
        "The function cannot be called \
         with exactly 1 argument of type '$Value' \
         as required to be set as a 'read' property.",
    )

    eval(quote
        vho(v::Value) = v.m
        vho!(v::Value, a, b) = v.m + a + b
    end)
    @method vho depends(Unf) read_as(vho)
    @methfails(
        (@method vho! depends(Unf) write_as(vho)),
        vho!,
        "The function cannot be called \
         with exactly 2 arguments, the first one being of type '$Value', \
         as required to be set as a 'write' property.",
    )

    # Disallow write-only properties.
    eval(quote
        tlc(v::Value, rhs) = (v.m = rhs)
    end)
    @methfails(
        (@method tlc depends(Unf) write_as(tlc)),
        tlc,
        "The property :tlc cannot be marked 'write' \
         without having first been marked 'read' for target '$System{$Value}'.",
    )

    # Guard against properties overrides.
    # (read)
    eval(quote
        vnq(v::Value) = v.m
    end)
    @method vnq depends(Unf) read_as(vnq)
    eval(quote
        fhh(v::Value) = v.m
    end)
    @methfails(
        (@method fhh depends(Unf) read_as(vnq)),
        fhh,
        "The property :vnq is already defined for target '$System{$Value}'."
    )

    # (write)
    eval(quote
        phs(v::Value) = v.m
        cll(v::Value) = v.m
        phs!(v::Value, rhs) = (v.m = rhs)
        cll!(v::Value, rhs) = (v.m = rhs)
    end)
    @method phs depends(Unf) read_as(phs)
    @method phs! depends(Unf) write_as(phs)
    @method cll depends(Unf) read_as(cll)
    @methfails(
        (@method cll! depends(Unf) write_as(phs)),
        cll!,
        "The property :phs is already marked 'write' for target '$System{$Value}'.",
    )

    #---------------------------------------------------------------------------------------
    # Guard against redundant sections.

    eval(quote
        function hlo end
    end)

    struct Xqd_b <: Blueprint{Value} end
    @blueprint Xqd_b
    @component Xqd{Value} blueprints(b::Xqd_b)

    @methfails(
        (@method hlo depends(Unf) depends(Xqd)),
        hlo,
        "The `depends` section is specified twice.",
    )

    @methfails(
        (@method hlo read_as(A) read_as(B)),
        hlo,
        "The :read_as section is specified twice.",
    )

    eval(:(module S # Also test nesting within modules?
    function redundant end
    end))

    @methfails(
        (@method S.redundant write_as(A) write_as(B)),
        S.redundant,
        "The :write_as section is specified twice.",
    )

    @methfails(
        (@method S.redundant write_as(A) read_as(B)),
        S.redundant,
        "Cannot specify both :write_as section and :read_as.",
    )

    # Guard against double specifications.
    Framework.REVISING = false
    eval(quote
        yqp(v::Value) = v.m
    end)
    @method yqp depends(Unf) read_as(yqp)
    @methfails(
        (@method yqp depends(Unf)),
        yqp,
        "Function '$yqp' already marked as a method for systems of '$Value'."
    )
    Framework.REVISING = true

end
end

# ==========================================================================================
module Abstracts
using ..MethodMacro
using EcologicalNetworksDynamics.Framework
using Main: @sysfails
using Test

# The plain value to wrap in a "system" in subsequent tests.
mutable struct Value
    _member::Union{Nothing,Int64}
    Value() = new(nothing)
end
Base.copy(v::Value) = deepcopy(v)
# Willing to enjoy wrapped value properties.
Base.getproperty(v::Value, p::Symbol) = Framework.unchecked_getproperty(v, p)
Base.setproperty!(v::Value, p::Symbol, rhs) = Framework.unchecked_setproperty!(v, p, rhs)
export Value

@testset "Abstract component semantics for @method." begin

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
    @blueprint B_b
    @blueprint C_b
    @blueprint D_b
    @component B <: A blueprints(b::B_b)
    @component C <: A blueprints(b::C_b)
    @component D <: A blueprints(b::D_b)

    eval(quote
        f(v::Value, x) = x + v._member
        get_prop(v::Value) = v._member
        set_prop!(v::Value, x) = (v._member = x)
    end)
    @method f depends(A)
    @method get_prop depends(A) read_as(prop)
    @method set_prop! depends(A) write_as(prop)

    s = System{Value}()
    @sysfails(f(s, 5), Method(f, "Requires a component $A."))
    @sysfails(s.prop, Property(prop, "A component $A is required to read this property."))
    @sysfails(
        (s.prop = 5),
        Property(prop, "A component $A is required to write to this property.")
    )

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
    @method tai depends(B) # Concrete.
    @method trt depends(A) # Abstract.
    @method rrk depends(tai, trt)
    @method dgw depends(trt, tai) # Order does not matter.
    @test collect(Framework.depends(System{Value}, rrk)) == [A] # Only.
    @test collect(Framework.depends(System{Value}, dgw)) == [A] # Only.

end
end

# ==========================================================================================
module PropertySpaces
using ..MethodMacro
using EcologicalNetworksDynamics.Framework
using Main: @sysfails, @methfails
using Test
const F = Framework

# The plain value to wrap in a "system" in subsequent tests.
mutable struct Value
    _member::Union{Nothing,Int64}
    Value() = new(nothing)
end
Base.copy(v::Value) = deepcopy(v)
# Willing to enjoy wrapped value properties.
Base.getproperty(v::Value, p::Symbol) = Framework.unchecked_getproperty(v, p)
Base.setproperty!(v::Value, p::Symbol, rhs) = Framework.unchecked_setproperty!(v, p, rhs)
export Value

@testset "Property spaces." begin

    check_props(s, expected) = @test sort(first.(properties(s))) == expected

    s = System{Value}()

    check_props(s, [])

    # Util to define property subspace.
    #! format: off
    @test @PropertySpace(a.b.c, Value) ===
        F.PropertySpace{:c,F.PropertySpace{:b,
                           F.PropertySpace{:a,System{Value},Value},Value},Value}
    #! format: on

    # Create a property space, accessible itself via a root property.
    eval(quote
        get_mre(::Value, s::System) = @PropertySpace(mre, Value)(s)
    end)
    @method get_mre{Value} read_as(mre)

    # Property appeared on the list.
    check_props(System{Value}, [:mre])
    check_props(s, [:mre]) # But this instance still has nothing.

    # Obtain the space.
    @test s.mre isa @PropertySpace(mre, Value)
    @sysfails((s.mre = 5), Property(mre, "This property is read-only."))

    # The space is still empty.
    @sysfails(s.mre.a, Property(mre.a, "Unknown property."))

    # Add property to the space.
    eval(quote
        get_htl(::Value) = "htl"
    end)
    @method get_htl{Value} read_as(mre.htl)

    # Check it out.
    check_props(@PropertySpace(mre, Value), [:htl])
    check_props(s.mre, [:htl])

    # Access the property.
    @test s.mre.htl == "htl"
    mre = s.mre # Delayed access.
    @test mre.htl == "htl"
    @sysfails((mre.htl = 5), Property(mre.htl, "This property is read-only."))

    # Inaccessible at the root level.
    @sysfails(s.htl, Property(htl, "Unknown property."))

    # Add subspace as yet another property.
    eval(quote
        get_txv(::Value, s::System) = @PropertySpace(mre.txv, Value)(s)
    end)
    @method get_txv{Value} read_as(mre.txv)
    @test s.mre.txv isa @PropertySpace(mre.txv, Value)

    # Add property to the subspace.
    eval(quote
        get_dru(::Value) = "dru"
    end)
    @method get_dru{Value} read_as(mre.txv.dru)
    @sysfails(s.mre.txv.a, Property(mre.txv.a, "Unknown property."))
    @sysfails(s.mre.dru, Property(mre.dru, "Unknown property."))
    @sysfails(s.dru, Property(dru, "Unknown property."))
    @test s.mre.txv.dru == "dru"

    # Property spaces can also require components to be read.
    struct Anq_b <: Blueprint{Value} end
    @blueprint Anq_b
    @component Anq{Value} blueprints(b::Anq_b)
    eval(quote
        get_goa(::Value, s::System) = @PropertySpace(goa, Value)(s)
        get_gyq(::Value, s::System) = @PropertySpace(goa.gyq, Value)(s)
    end)
    @method get_goa{Value} read_as(goa)
    @method get_gyq depends(Anq) read_as(goa.gyq)

    # Both type/instance yield same results..
    check_props(System{Value}, [:goa, :mre])
    check_props(s, [:goa, :mre])
    # .. unless the instance misses dependencies.
    check_props(@PropertySpace(goa, Value), [:gyq])
    check_props(s.goa, [])

    @sysfails(
        s.goa.gyq,
        Property(goa.gyq, "Component $_Anq is required to read this property.")
    )
    goa = s.goa # Delayed access.
    @sysfails(
        goa.gyq,
        Property(goa.gyq, "Component $_Anq is required to read this property.")
    )
    s += Anq.b()
    @test s.goa.gyq isa @PropertySpace(goa.gyq, Value)

    # Writable accesses.
    eval(quote
        set_htl!(v::Value, rhs) = (v._member = rhs)
    end)

    @methfails(
        (@method set_htl!{Value} write_as(htl)),
        set_htl!,
        "The property :htl cannot be marked 'write' \
         without having first been marked 'read' for target '$System{$Value}'."
    )

    @methfails(
        (@method set_htl!{Value} write_as(mre.a)),
        set_htl!,
        "The property :(mre.a) cannot be marked 'write' \
         without having first been marked 'read' \
         for target '$(F.PropertySpace){<.mre>, $Value}'."
    )

    # Finally succeed.
    @method set_htl!{Value} write_as(mre.htl)

    @test isnothing(s._value._member)
    s.mre.htl = 5
    @test s._value._member == 5
    mre = s.mre # Delayed access.
    mre.htl = 8
    @test s._value._member == 8

    # Dependent write.
    struct Vnq_b <: Blueprint{Value} end
    @blueprint Vnq_b
    @component Vnq{Value} blueprints(b::Vnq_b)
    eval(quote
        get_nbu(v::Value) = v._member
        set_nbu!(v::Value, rhs) = (v._member = rhs + 1)
    end)
    @method get_nbu{Value} read_as(goa.gyq.nbu)
    @method set_nbu! depends(Vnq) write_as(goa.gyq.nbu)

    @test s.goa.gyq.nbu == 8
    @sysfails(
        (s.goa.gyq.nbu = 9),
        Property(goa.gyq.nbu, "Component $_Vnq is required to write to this property.")
    )
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
    @method get_orw{Value} read_as(orw, goa.orw, goa.gyq.orw)
    @test s.orw == s.goa.orw == s.goa.gyq.orw == "orw"

    # Same dependencies for all aliases.
    s = System{Value}(Anq.b())
    eval(quote
        get_btt(::Value) = "btt"
    end)
    @method get_btt depends(Vnq) read_as(btt, goa.btt, goa.gyq.btt)

    @sysfails(s.btt, Property(btt, "Component $_Vnq is required to read this property."))
    @sysfails(
        s.goa.btt,
        Property(goa.btt, "Component $_Vnq is required to read this property.")
    )
    @sysfails(
        s.goa.gyq.btt,
        Property(goa.gyq.btt, "Component $_Vnq is required to read this property.")
    )
    s += Vnq.b()
    @test s.btt == s.goa.btt == s.goa.gyq.btt == "btt"

    # Dependent write aliases.
    struct Tkq_b <: Blueprint{Value} end
    @blueprint Tkq_b
    @component Tkq{Value} blueprints(b::Tkq_b)
    eval(quote
        set_btt!(v::Value, rhs) = (v._member = 10 * rhs)
    end)
    @method set_btt! depends(Tkq) write_as(btt, goa.btt, goa.gyq.btt)

    @sysfails(
        (s.btt = 44),
        Property(btt, "Component $_Tkq is required to write to this property.")
    )
    @sysfails(
        (s.goa.btt = 44),
        Property(goa.btt, "Component $_Tkq is required to write to this property.")
    )
    @sysfails(
        (s.goa.gyq.btt = 44),
        Property(goa.gyq.btt, "Component $_Tkq is required to write to this property.")
    )
    s += Tkq.b()
    s.btt = 44
    @test s._value._member == 440
    s.goa.btt = 55
    @test s._value._member == 550
    s.goa.gyq.btt = 66
    @test s._value._member == 660

end

end

end

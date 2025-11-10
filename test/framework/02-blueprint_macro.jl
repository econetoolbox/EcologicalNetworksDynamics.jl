module Blueprints

using EcologicalNetworksDynamics.Framework

# Testing these macros requires generating numerous new types
# which are bound to constant julia variables.
# In particular, testing macros for *failure* typically results
# in generated code aborting halway through their expansion/execution
# and make it likely that unexpected interactions occur between subsequent tests
# if the names of generated blueprints/components collide.
# Alleviate this by picking random trigrams for the tests:
#   - `Xyz` as component names
#   - `Xyz_b` as associated blueprint names.

# The plain value to wrap in a "system" in subsequent tests.
struct Value
    d::Dict{Symbol,Any}
    Value() = new(Dict())
end
Base.copy(v::Value) = deepcopy(v)
Base.getproperty(s::Framework.System{Value}, name::Symbol) =
    name in fieldnames(System) ? getfield(s, name) : s._value.d[name]
export Value

# ==========================================================================================
module Invocations
using ..Blueprints
using EcologicalNetworksDynamics.Framework
using Main: @failswith, @sysfails, @pbluefails, @xbluefails
using Test
using Crayons
const F = Framework

const S = System{Value}
comps(s) = collect(components(s))

@testset "Valid @blueprint macro invocations." begin

    # Basic use: empty blueprint.
    struct Gdu_b <: Blueprint{Value} end
    @blueprint Gdu_b # (that's all it takes)

    # Works with a component to expand into.
    @component Gdu{Value} blueprints(b::Gdu_b)
    s = System{Value}(Gdu.b())
    @test has_component(s, Gdu)

    # Any expression can be given if it evaluates to expected macro input.
    struct Tap_b <: Blueprint{Value} end

    ev_count = [0] # (check that the expression is only evaluated once)
    function value_expression()
        ev_count[1] += 1
        Tap_b
    end

    @blueprint value_expression()

    # Works as expected.
    @component Tap{Value} blueprints(b::Tap_b)
    @test has_component(System{Value}(Tap.b()), Tap)

    # Only evaluated once.
    @test ev_count == [1]

    # Add a short descriptive string.
    struct Fjr_b <: Blueprint{Value} end
    @blueprint Fjr_b "description for Fjr_b"
    @component Fjr{Value} blueprints(b::Fjr_b)
    @test sprint(F.shortline, Fjr_b) == "description for Fjr_b"

    # Add a expansion-time dependency.
    struct Vkl_b <: Blueprint{Value} end
    @blueprint Vkl_b
    @component Vkl{Value} blueprints(b::Vkl_b)

    struct Zav_b <: Blueprint{Value} end
    @blueprint Zav_b "" depends(Vkl => "Zav likes Vkl") # Same syntax/logic as @component.
    @component Zav{Value} blueprints(b::Zav_b)


    s = System{Value}()
    @sysfails((s + Zav.b()), Missing(Vkl, nothing, [Zav.b], "Zav likes Vkl"))
    s += Vkl.b()
    # Now it's okay.
    s += Zav.b()
    @test has_component(s, Vkl)
    @test has_component(s, Zav)

    # Elide reason.
    struct Ovm_b <: Blueprint{Value} end
    @blueprint Ovm_b "" depends(Vkl)
    @component Ovm{Value} blueprints(b::Ovm_b)
    @sysfails((System{Value}(Ovm.b())), Missing(Vkl, nothing, [Ovm.b], nothing))

end

@testset "Invalid @blueprint macro invocations." begin

    @pbluefails(
        (@blueprint),
        "Not enough macro input provided. Example usage:\n\
         | @blueprint Name \"short description\" depends(Components...)\n"
    )

    @pbluefails(
        (@blueprint a b c d),
        "Too much macro input provided. Example usage:\n\
         | @blueprint Name \"short description\" depends(Components...)\n"
    )

    @xbluefails(
        (@blueprint Cpf),
        nothing,
        "Blueprint type: expression does not evaluate: :Cpf. \
        (See error further down the exception stack.)"
    )

    Zmw_b = 5
    @xbluefails(
        (@blueprint Zmw_b),
        nothing,
        "Blueprint type: expression does not evaluate to a 'DataType':\n\
         Expression: :Zmw_b\n\
         Result: 5 ::$Int"
    )

    @xbluefails(
        (@blueprint 4 + 5),
        nothing,
        "Blueprint type: expression does not evaluate to a 'DataType':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @xbluefails(
        (@blueprint Vector{Int}),
        Vector{Int},
        "Not a subtype of '$Blueprint': 'Vector{$Int}'."
    )

    struct Xgi end
    @xbluefails((@blueprint Xgi), Xgi, "Not a subtype of '$Blueprint': '$Xgi'.")

    abstract type Hek <: Blueprint{Value} end
    @xbluefails(
        (@blueprint Hek),
        Hek,
        "Cannot define blueprint from an abstract type: '$Hek'."
    )

    struct Eap <: Blueprint{Value} end
    @blueprint Eap
    @xbluefails(
        (@blueprint Eap),
        Eap,
        "Type '$Eap' already marked as a blueprint for systems of '$Value'."
    )

end

using Logging

@testset "Brought fields: valid uses." begin

    #---------------------------------------------------------------------------------------
    # Definition.

    # Empty blueprint to be brought.
    struct Xhu_b <: Blueprint{Value} end
    @blueprint Xhu_b
    @component Xhu{Value} blueprints(b::Xhu_b)

    # Blueprint with data to be brought.
    struct Ejp_b <: Blueprint{Value}
        u::Int64
        v::Int64
    end
    function F.expand!(v, ejp::Ejp_b)
        v.d[:u] = ejp.u
        v.d[:v] = ejp.v
    end
    @blueprint Ejp_b
    @component Ejp{Value} blueprints(b::Ejp_b)

    # Forget to specify how to construct implied blueprints.
    mutable struct Bdz_b <: Blueprint{Value}
        x::Float64
        y::Float64
        xhu::Brought(Xhu)
        ejp::Brought(Ejp)
    end
    F.implied_blueprint_for(::Bdz_b, ::Type{_Xhu}) = Xhu.b() # Regular method signature.
    F.implied_blueprint_for(::Bdz_b, ::_Ejp) = Ejp.b(5, 8) # Convenience method signature.
    @blueprint Bdz_b
    @component Bdz{Value} blueprints(b::Bdz_b)

    #---------------------------------------------------------------------------------------
    # Use.

    # Bring nothing.
    bdz = Bdz_b(1, 2, nothing, nothing)
    @test comps(S(bdz)) == [Bdz]
    @test comps(S(Xhu.b(), bdz)) == [Xhu, Bdz]
    s = S(Xhu.b(), Ejp.b(1, 2), bdz)
    @test comps(s) == [Xhu, Ejp, Bdz]
    @test (s.u, s.v) == (1, 2)

    # Imply component.
    s = S(Bdz_b(1, 2, nothing, Ejp))
    @test comps(s) == [Ejp, Bdz]
    @test (s.u, s.v) == (5, 8) # Default ones.

    # Only bring the ones missing.
    #    already here                  implied
    #     vvvvvvvvvvv                   vvv
    s = S(Ejp.b(4, 5), Bdz_b(1, 2, Xhu, Ejp))
    @test comps(s) == [Ejp, Xhu, Bdz]
    @test (s.u, s.v) == (4, 5) # (not the implied one)

    # Embed blueprints.
    s = S(Bdz_b(1, 2, Xhu.b(), Ejp.b(15, 30)))
    @test comps(s) == [Xhu, Ejp, Bdz]
    @test (s.u, s.v) == (15, 30)

    # It's an error to embed into a system when it's already there.
    @sysfails(
        S(Xhu.b(), Bdz_b(1, 2, Xhu.b(), Ejp.b(15, 30))),
        Add(BroughtAlreadyInValue, Xhu, [Xhu_b, false, Bdz_b]),
    )

    # Same tests, but from a blueprint modified on the fly.
    bdz = Bdz_b(1, 2, nothing, nothing)
    # Imply.
    bdz.ejp = Ejp
    s = S(bdz)
    @test comps(s) == [Ejp, Bdz]
    @test (s.u, s.v) == (5, 8)
    # Only bring the ones missing.
    bdz.xhu = Xhu
    s = S(Ejp.b(4, 5), bdz)
    @test comps(s) == [Ejp, Xhu, Bdz]
    @test (s.u, s.v) == (4, 5) # (not the implied one)
    # Embed.
    bdz.ejp = Ejp.b(15, 30)
    s = S(bdz)
    @test comps(s) == [Xhu, Ejp, Bdz]
    @test (s.u, s.v) == (15, 30)

    # Embed using implicit blueprint construction.
    (::typeof(Ejp))(u, v; shift = 0) = Ejp.b(u + shift, v + shift)

    # As field assignments.
    bdz.ejp = (15, 30)
    s = S(bdz)
    @test comps(s) == [Xhu, Ejp, Bdz]
    @test (s.u, s.v) == (15, 30)

    # As constructor arguments.
    bdz = Bdz_b(1, 2, nothing, (15, 30))
    s = S(bdz)
    @test comps(s) == [Ejp, Bdz]
    @test (s.u, s.v) == (15, 30)

    # Constructors accept keyword arguments.
    bdz = Bdz_b(1, 2, nothing, ((15, 30), (; shift = 2))) # ← The way to use it.
    s = S(bdz)
    @test comps(s) == [Ejp, Bdz]
    @test (s.u, s.v) == (17, 32)

    bdz.ejp = ((15, 30), (; shift = 5)) # ← The way to use it again.
    s = S(bdz)
    @test comps(s) == [Ejp, Bdz]
    @test (s.u, s.v) == (20, 35)

end

@testset "Brought fields: invalid uses." begin

    @failswith(Brought(5), MethodError)
    @failswith(Brought(Int), MethodError)
    @failswith(Brought(Vector{Int}), MethodError)
    @failswith(Brought(Vector), MethodError)
    @failswith(Brought(F.Component), MethodError)
    struct Amg_b <: Blueprint{Value} end
    @blueprint Amg_b
    @failswith(Brought(Amg_b), MethodError)

    #---------------------------------------------------------------------------------------
    # Implied blueprint constructors.

    # Forgot to define it.
    struct Ihb_b <: Blueprint{Value}
        x::Float64
        y::Float64
        xhu::Brought(Xhu)
        ejp::Brought(Ejp)
    end
    @xbluefails(
        (@blueprint Ihb_b),
        Ihb_b,
        "Method implied_blueprint_for($Ihb_b, <$Xhu>) unspecified \
         to implicitly bring <$Xhu> from $Ihb_b blueprints."
    )

    # Define one, but not the other.
    F.implied_blueprint_for(::Ihb_b, ::Type{_Xhu}) = Xhu.b() # Regular method signature.
    @xbluefails(
        (@blueprint Ihb_b),
        Ihb_b,
        "Method implied_blueprint_for($Ihb_b, <$Ejp>) unspecified \
         to implicitly bring <$Ejp> from $Ihb_b blueprints."
    )
    F.implied_blueprint_for(::Ihb_b, ::_Ejp) = Ejp.b(5, 8) # Convenience method signature.

    # Now it's okay.
    @blueprint Ihb_b

    # Can't define both the regular *and* convenience methods.
    struct Ntz_b <: Blueprint{Value}
        xhu::Brought(Xhu)
    end
    F.implied_blueprint_for(::Ntz_b, ::_Xhu) = Xhu.b()
    F.implied_blueprint_for(::Ntz_b, ::Type{_Xhu}) = Xhu.b()
    @xbluefails(
        (@blueprint Ntz_b),
        Ntz_b,
        "Ambiguity: the two following methods have been defined:\n  \
           $(F.implied_blueprint_for)(::$Ntz_b, ::<$Xhu>)\n  \
           $(F.implied_blueprint_for)(::$Ntz_b, ::Type{<$Xhu>})\n\
         Consider removing either one."
    )

    #---------------------------------------------------------------------------------------
    # Guard against redundant brought blueprints.
    struct Qev_b <: Blueprint{Value}
        data::Brought(Ejp)
        other::Brought(Ejp)
    end
    F.implied_blueprint_for(::Qev_b, ::_Ejp) = Ejp.b(5, 8)
    @xbluefails(
        (@blueprint Qev_b),
        Qev_b,
        "Both fields 'data' and 'other' potentially bring <$Ejp>.",
    )

    # Redundancy is guarded through abstract component hierarchy.
    abstract type TopComp <: Component{Value} end
    struct Agf_b <: Blueprint{Value} end
    @blueprint Agf_b
    @component BottomComp <: TopComp blueprints(b::Agf_b)

    struct Jzd_b <: Blueprint{Value}
        sup::Brought(TopComp)
        sub::Brought(BottomComp)
    end
    F.implied_blueprint_for(::Jzd_b, ::TopComp) = Agf.b()
    F.implied_blueprint_for(::Jzd_b, ::_BottomComp) = Agf.b()
    @xbluefails(
        (@blueprint Jzd_b),
        Jzd_b,
        "Fields 'sub' and 'sup': \
         brought blueprint <$BottomComp> \
         is also specified as $TopComp."
    )

    #---------------------------------------------------------------------------------------
    # Implicit brought blueprints constructor.

    struct Opv_b <: Blueprint{Value} end
    @blueprint Opv_b
    @component Opv{Value} blueprints(b::Opv_b)
    mutable struct Twt_b <: Blueprint{Value}
        opv::Brought(Opv)
    end
    F.implied_blueprint_for(::Twt_b, ::_Opv) = Opv.b()
    @blueprint Twt_b
    @component Twt{Value} blueprints(b::Twt_b)
    twt = Twt_b(nothing)

    # Check both failure on constructor and on field assignment.
    input = () # (rebind to not trigger the 'WARNING: Method definition overwritten')
    constructed = nothing # (same)
    erm = nothing # (same)
    bcf() = F.BroughtConvertFailure(_Opv, erm, input)
    baf() = F.BroughtAssignFailure(Twt_b, :opv, bcf())

    # Can't call if undefined.
    erm = "'$Opv' is not (yet?) callable. \
           Consider providing a blueprint value instead."
    @failswith(Twt_b(()), bcf())
    @failswith((twt.opv = ()), baf())

    # Must construct a consistent blueprint.
    (::typeof(Opv))() = constructed
    red, res = (crayon"bold red", crayon"reset")
    bug = "\n$(red)This is a bug in the components library.$res"

    # Not a blueprint.
    constructed = 5
    erm = "Implicit blueprint constructor did not yield a blueprint, but: 5 ::$Int.$bug"
    @failswith(Twt_b(()), bcf())
    @failswith((twt.opv = ()), baf())

    # Not for the right value type.
    struct Yfi_b <: Blueprint{Int} end
    constructed = Yfi_b()
    erm = "Implicit blueprint constructor did not yield a blueprint for '$Value', \
           but for '$Int': $Yfi_b().$bug"
    @failswith(Twt_b(()), bcf())
    @failswith((twt.opv = ()), baf())

    # Not for the right component*s.
    struct Sxo_b <: Blueprint{Value} end
    @blueprint Sxo_b
    @component Iej{Value}
    @component Axl{Value}
    F.componentsof(::Sxo_b) = [Iej, Axl]
    constructed = Sxo_b()
    erm = "Implicit blueprint constructor yielded instead \
           a blueprint for: [$Iej, $Axl].$bug"
    @failswith(Twt_b(()), bcf())
    @failswith((twt.opv = ()), baf())

    # Not for the right component.
    struct Dpt_b <: Blueprint{Value} end
    @blueprint Dpt_b
    @component Dpt{Value} blueprints(b::Dpt_b)
    constructed = Dpt_b()
    erm = "Implicit blueprint constructor yielded instead a blueprint for: <$Dpt>.$bug"
    @failswith(Twt_b(()), bcf())
    @failswith((twt.opv = ()), baf())

    # No corresponding method for the constructor.
    input = 5
    erm = "No method matching $Opv(5). (See further down the stacktrace.)"
    @failswith(Twt_b(input), bcf())
    @failswith((twt.opv = input), baf())

    input = (5, 8)
    erm = "No method matching $Opv(5, 8). (See further down the stacktrace.)"
    @failswith(Twt_b(input), bcf())
    @failswith((twt.opv = input), baf())

    input = (; c = 13)
    erm = "No method matching $Opv(; c = 13). (See further down the stacktrace.)"
    @failswith(Twt_b(input), bcf())
    @failswith((twt.opv = input), baf())

    input = ((5, 8), (; c = 13))
    erm = "No method matching $Opv(5, 8; c = 13). (See further down the stacktrace.)"
    @failswith(Twt_b(input), bcf())
    @failswith((twt.opv = input), baf())

end
end

# ==========================================================================================
module Abstracts
using ..Blueprints
using EcologicalNetworksDynamics.Framework
using Main: @failswith, @sysfails, @pcompfails, @xcompfails, @xbluefails
using Test
using Crayons
const F = Framework

const S = System{Value}
comps(s) = sort(collect(components(s)); by = repr)

@testset "Bringing abstract component types." begin

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

    # ======================================================================================
    # Invalid uses.

    mutable struct Pmi_b <: Blueprint{Value}
        a::Brought(A)
    end
    F.implied_blueprint_for(::Pmi_b, ::Type{A}) = B.b()
    @blueprint Pmi_b
    @component Pmi{Value} blueprints(b::Pmi_b)
    pmi = Pmi.b(nothing)

    # Consistent values must be given to brought fields.
    #   - Either during blueprint construction.
    #   - Or during field assignments.
    #   - Or as the result of calls to implicit brought constructor.
    input = nothing
    erm = nothing
    bcf() = F.BroughtConvertFailure(A, erm, input)
    baf() = F.BroughtAssignFailure(Pmi.b, :a, bcf())
    red, res = (crayon"bold red", crayon"reset")
    bug = "\n$(red)This is a bug in the components library.$res"

    # Abstract component has not yet been turned into a constructor.
    input = ()
    erm = "'$A' is not (yet?) callable. \
           Consider providing a blueprint value instead."
    @failswith(Pmi.b(), MethodError)
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # Now defined.
    A() = input

    # Not a blueprint.
    input = 5
    erm = "No method matching $A(5). (See further down the stacktrace.)"
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # Not a blueprint for the right value type.
    struct Tcv_b <: Blueprint{Int} end
    @blueprint Tcv_b
    @component Tcv{Int} blueprints(b::Tcv_b)
    input = Tcv.b()
    erm = "The input does not embed a blueprint for '$Value', but for '$Int'."
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # Not a blueprint for the right component*s.
    struct Trl_b <: Blueprint{Value} end
    @blueprint Trl_b
    @component Trl{Value}
    @component Oyt{Value}
    @component Yxt{Value}
    F.componentsof(::Trl_b) = [Oyt, Yxt]
    input = Trl_b()
    erm = "Blueprint would instead expand into [$Oyt, $Yxt]."
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # Not a blueprint for a component subtyping A.
    struct Mjv_b <: Blueprint{Value} end
    @blueprint Mjv_b
    @component Mjv{Value} blueprints(b::Mjv_b)
    input = Mjv.b()
    erm = "Blueprint would instead expand into <$Mjv>."
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())
    erm = "Implicit blueprint constructor yielded instead a blueprint for: <$Mjv>.$bug"
    err = F.BroughtConvertFailure(A, erm, ())
    @failswith(Pmi.b(()), err)
    @failswith((pmi.a = ()), F.BroughtAssignFailure(Pmi_b, :a, err))

    # Not an implied component for the right value type.
    @component Mbl{Int}
    input = Mbl
    erm = "The input would not imply a component for '$Value', but for '$Int'."
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())
    input = _Mbl # (same with actual component type)
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # Not an implied component subtyping A.
    @component Cif{Value}
    input = Cif
    erm = "The input would instead imply <$Cif>."
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())
    input = _Cif
    @failswith(Pmi.b(input), bcf())
    @failswith((pmi.a = input), baf())

    # An implied component subtyping A,
    # but with no implicit constructor defined.
    input = B
    Pmi.b(input) # TODO: find a way to error at this point..
    pmi.a = input # .. or this point..
    @failswith(S(pmi), F.UnimplementedImpliedMethod(Pmi_b, A, _B)) # .. rather than then.

    # ======================================================================================
    # Valid uses.

    mutable struct Wmu_b <: Blueprint{Value}
        a::Brought(A)
    end
    F.implied_blueprint_for(::Wmu_b, ::Type{A}) = B.b() # Any is ok.
    @blueprint Wmu_b
    @component Wmu{Value} blueprints(b::Wmu_b)
    # Not brought.
    s = S(Wmu_b(nothing))
    @test !has_component(s, A)
    @test comps(s) == [Wmu]
    # Implied.
    s = S(Wmu_b(A))
    @test has_component(s, A)
    @test comps(s) == [B, Wmu] # B is actually brought.
    # Embedded.
    s = S(Wmu_b(B.b()))
    @test has_component(s, A)
    @test comps(s) == [B, Wmu] # B is actually brought.
    # Embedding another is ok..
    s = S(Wmu_b(D.b()))
    @test has_component(s, A) # ← ..because this still holds.
    @test comps(s) == [D, Wmu] # D is actually brought.

    # Implicit blueprint constructor can bring any sub-component.
    input = C.b() # Say (defined output of `A()` constructor (see tests above))
    s = S(Wmu.b(()))
    @test comps(s) == [C, Wmu]
    @test has_component(s, A)

    # Accept any sub-component as implied.
    F.implied_blueprint_for(::Wmu_b, ::_B) = B.b() # (convenience form)
    F.implied_blueprint_for(::Wmu_b, ::Type{_C}) = C.b() # (longer explicit form)
    F.implied_blueprint_for(::Wmu_b, ::_D) = D.b()

    wmu = Wmu.b(nothing)
    wmu.a = A
    @test comps(S(wmu)) == [B, Wmu] # Get the default.
    wmu.a = B
    @test comps(S(wmu)) == [B, Wmu] # Get the implied one, but explicitly.
    wmu.a = C
    @test comps(S(wmu)) == [C, Wmu]
    wmu.a = D
    @test comps(S(wmu)) == [D, Wmu]

    # Accept any sub-component as embedded.
    wmu.a = B.b()
    @test comps(S(wmu)) == [B, Wmu]
    wmu.a = C.b()
    @test comps(S(wmu)) == [C, Wmu]
    wmu.a = D.b()
    @test comps(S(wmu)) == [D, Wmu]

    # Expanding from an abstract component.
    struct Som_b <: Blueprint{Value} end
    @blueprint Som_b "" depends(A)
    @component Som{Value} blueprints(b::Som_b)
    @test isempty(F.requires(Som)) # The component requires nothing..
    # .. but expansion of this blueprint does.
    @sysfails(S(Som.b()), Missing(A, nothing, [Som.b], nothing))
    # Any concrete component A enables expansion.
    s = S(B.b(), Som.b())
    @test comps(s) == [B, Som]
    @test has_component(s, A) # Same B but as an abstract A.

end
end
end

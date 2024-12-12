module ComponentMacro

# Testing these macros requires to generate numerous new types
# which are bound to constant julia variables.
# In particular, testing macros for *failure*
# typically result in generated code aborting halway through their expansion/execution
# and make it likely that unexpected interactions occur between subsequent tests
# if the names of generated blueprints/components collide.
# Alleviate this by picking random trigrams for the tests:
#   - `Xyz` as component names
#   - `Xyz_b` as associated blueprint names.

# The plain value to wrap in a "system" in subsequent tests.
struct Value end
Base.copy(v::Value) = deepcopy(v)
export Value

# ==========================================================================================
module Invocations
using ..ComponentMacro
using EcologicalNetworksDynamics.Framework
using Main: @sysfails, @pcompfails, @xcompfails, @failswith
const F = Framework
using Test

const S = System{Value}
comps(s) = collect(components(s))

# Testing blueprint collectiong from module.
# (must be declared at toplevel)
module Plv_b
using ..F
using ..Invocations: Value
struct Ibh_b <: Blueprint{Value} end # Collected.
struct Fek_b <: Blueprint{Value} end # Collected.
struct Zpp_b <: Blueprint{Value} end # Not collected (not exported)
struct Qqu_b <: Blueprint{Int} end # Not collected (not for 'Value').
@blueprint Ibh_b
@blueprint Fek_b
@blueprint Zpp_b
@blueprint Qqu_b
# Not collected.
a = 5
const b = 8
struct Wec end
export Ibh_b, Fek_b, Qqu_b, a, b, Wec
end

module Zru end # Test empty module.

@testset "Invocation variations of @component macro." begin

    #---------------------------------------------------------------------------------------
    # Basic, null component.

    @component Eyb{Value}

    # Creation of the singleton type and its instance.
    @test Eyb isa _Eyb
    @test _Eyb <: Component{Value}

    # But there is no blueprint to expand into it.
    @failswith(Eyb(), MethodError)

    #---------------------------------------------------------------------------------------
    # Alternate syntax in a block.

    @component begin
        Iew{Value}
    end
    @test Iew isa _Iew
    @test _Iew <: Component{Value}
    @failswith(Iew(), MethodError)

    #---------------------------------------------------------------------------------------
    # With a basic blueprint.

    # '_b' for the blueprint associated with component `Sem`
    struct Sem_b <: Blueprint{Value} end
    @blueprint Sem_b
    @component Sem{Value} blueprints(b::Sem_b)

    # The blueprint is 'namespaced' within the component singleton.
    @test Sem.b === Sem_b

    # And we can use it to expand into a component.
    s = System{Value}(Sem.b())
    @test has_component(s, Sem)

    #---------------------------------------------------------------------------------------
    # Alternate syntax in a block.

    struct Olk_b <: Blueprint{Value} end
    @blueprint Olk_b
    @component begin
        Olk{Value}
        blueprints(b::Olk_b)
    end

    @test Olk.b === Olk_b
    s = System{Value}(Olk.b())
    @test has_component(s, Olk)

    #---------------------------------------------------------------------------------------
    # Require other component.

    struct Cvh_b <: Blueprint{Value} end
    struct Zjz_b <: Blueprint{Value} end
    @blueprint Cvh_b
    @blueprint Zjz_b

    @component Cvh{Value} blueprints(b::Cvh_b)
    @component Zjz{Value} blueprints(b::Zjz_b) requires(Cvh)

    @test collect(F.requires(Cvh)) == []
    @test collect(F.requires(Zjz)) == [_Cvh => nothing]

    s = System{Value}()
    # Cannot add Zjz without Cvh.
    @sysfails((s + Zjz.b()), Missing(Cvh, _Zjz, [Zjz_b], nothing))
    s += Cvh.b() # Meet the requirement.
    s += Zjz.b() # Now it's okay.
    @test collect(components(s)) == [Cvh, Zjz]

    #---------------------------------------------------------------------------------------
    # Alternate syntax in blocks.

    struct Dsy_b <: Blueprint{Value} end
    struct Lev_b <: Blueprint{Value} end
    @blueprint Dsy_b
    @blueprint Lev_b

    @component Dsy{Value} blueprints(b::Dsy_b)
    # (alternate syntax)
    @component begin
        Lev{Value}
        blueprints(b::Lev_b)
        requires(_Dsy) # Okay to use component *type* instead.
    end

    @test collect(F.requires(Dsy)) == []
    @test collect(F.requires(Lev)) == [_Dsy => nothing]

    s = System{Value}()
    @sysfails((s + Lev.b()), Missing(Dsy, _Lev, [Lev_b], nothing))
    s += Dsy.b() + Lev.b()
    @test collect(components(s)) == [Dsy, Lev]

    #---------------------------------------------------------------------------------------
    # Explicit empty lists.

    @component Nzo{Value} blueprints() requires()
    @test fieldnames(_Nzo) == () # No blueprints listed.
    @test collect(F.requires(Nzo)) == [] # No requirements.

    # Test with a constructible one that it does require nothing.
    struct Lwk_b <: Blueprint{Value} end
    @blueprint Lwk_b
    @component Lwk{Value} blueprints(b::Lwk_b) requires()
    s = System{Value}(Lwk.b())
    @test has_component(s, Lwk)

    #---------------------------------------------------------------------------------------
    # Any expression can be given in 'require' if it evaluates to expected macro input.

    struct Tap_b <: Blueprint{Value} end
    struct Dsn_b <: Blueprint{Value} end
    @blueprint Tap_b
    @blueprint Dsn_b

    @component Tap{Value} blueprints(b::Tap_b)

    tap_count = [0] # (check that it's only evaluated once as expected)
    dsn_count = [0]
    function tap_expression()
        tap_count[1] += 1
        Tap
    end
    function dsn_expression()
        dsn_count[1] += 1
        Dsn_b
    end

    # Use arbitrary expression instead of identifier paths.
    @component Dsn{Value} blueprints(b::dsn_expression()) requires(tap_expression())

    # The requirement works..
    s = System{Value}()
    @sysfails((s + Dsn.b()), Missing(Tap, _Dsn, [Dsn_b], nothing))
    s += Tap.b() + Dsn.b()
    @test collect(components(s)) == [Tap, Dsn]
    # .. and the expressions have only been evaluated once to this end.
    @test tap_count == [1]
    @test dsn_count == [1]

end

@testset "Invalid @component macro invocations." begin

    #---------------------------------------------------------------------------------------
    # Basic misuses.

    @pcompfails((@component), ["Not enough macro input provided. Example usage:\n"])

    @pcompfails((@component a b c d e), ["Too much macro input provided. Example usage:\n"])

    @pcompfails(
        (@component 4 + 5),
        "Expected component `Name{ValueType}` or `Name <: SuperComponent`, \
         got instead: :(4 + 5)."
    )

    @pcompfails(
        (@component Vector),
        "Expected component `Name{ValueType}` or `Name <: SuperComponent`, \
         got instead: :Vector."
    )

    @xcompfails(
        (@component Oan{NotAType}),
        nothing,
        "Evaluating given system value type: \
         expression does not evaluate: :NotAType. \
         (See error further down the exception stack.)"
    )

    @xcompfails(
        (@component Vector{Int64}),
        nothing,
        "Cannot define component 'Vector': name already defined."
    )

    @component Rrn{Value}
    @xcompfails(
        (@component Rrn{Int64}),
        nothing,
        "Cannot define component 'Rrn': name already defined."
    )

    @pcompfails(
        (@component Eft{Value} wrong()),
        "Invalid @component section. Expected `requires(..)` or `blueprints(..)`, \
         got instead: :(wrong())."
    )

    @pcompfails(
        (@component Ohk{Value} struct NotASection end),
        ["Invalid @component section. Expected `requires(..)` or `blueprints(..)`, \
          got instead: :(struct NotASection"],
    )

    #---------------------------------------------------------------------------------------
    # Blueprints section.

    @pcompfails(
        (@component Uvv{Value} blueprints(4 + 5)),
        "Expected `name::Type` or `ModuleName` to specify blueprint, \
         found instead: :(4 + 5).",
    )

    @xcompfails(
        (@component Uvv{Value} blueprints(b::(4 + 5))),
        :Uvv,
        "Blueprint: expression does not evaluate to a 'DataType':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int",
    )

    @xcompfails(
        (@component Uvv{Value} blueprints(b::Int)),
        :Uvv,
        "Blueprint: '$Int64' does not subtype '$Blueprint{$Value}'.",
    )

    # The given blueprint(s) need to target the same type.
    struct Uvv_i <: Blueprint{Int} end
    @blueprint Uvv_i
    @xcompfails(
        (@component Uvv{Value} blueprints(b::Uvv_i)),
        :Uvv,
        "Blueprint: '$Uvv_i' does not subtype '$Blueprint{$Value}', but '$Blueprint{$Int}'.",
    )

    # Guard against redundancy / collisions.
    struct Uvv_b <: Blueprint{Value} end
    @blueprint Uvv_b
    @xcompfails(
        (@component Uvv{Value} blueprints(b::Uvv_b, c::Uvv_b)),
        :Uvv,
        "Base blueprint '$Uvv_b' bound to both names :b and :c.",
    )

    struct Uvv_c <: Blueprint{Value} end
    @blueprint Uvv_c
    @xcompfails(
        (@component Uvv{Value} blueprints(b::Uvv_b, b::Uvv_c)),
        :Uvv,
        "Base blueprint :b both refers to '$Uvv_b' and to '$Uvv_c'.",
    )

    # Collect blueprints from exporte module identifiers.
    struct Yrv_b <: Blueprint{Value} end
    @blueprint Yrv_b
    @component Plv{Value} blueprints(b::Yrv_b, Plv_b)

    # Those exported from the module have been added.
    @test fieldnames(_Plv) == (:b, :Ibh_b, :Fek_b)
    @test Plv.b == Yrv_b
    @test Plv.Ibh_b == Plv_b.Ibh_b
    @test Plv.Fek_b == Plv_b.Fek_b

    @xcompfails(
        (@component Fyi{Value} blueprints(Plv_b, dupe::Plv_b.Fek_b)),
        :Fyi,
        "Base blueprint '$(Plv_b.Fek_b)' bound to both names :Fek_b and :dupe."
    )

    @xcompfails(
        (@component Kxi{Value} blueprints(Zru)),
        :Kxi,
        "Module '$Zru' exports no blueprint for '$Value'."
    )


    #---------------------------------------------------------------------------------------
    # Requires section.

    @xcompfails(
        (@component Kpr{Value} requires(Undefined)),
        :Kpr,
        "Required component: expression does not evaluate: :Undefined. \
        (See error further down the exception stack.)"
    )

    @xcompfails(
        (@component Kpr{Value} requires(4 + 5)),
        :Kpr,
        "Required component: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @xcompfails(
        (@component Kpr{Value} requires(Int)),
        :Kpr,
        "Required component: expression does not evaluate \
         to a subtype of '$Component':\n\
         Expression: :Int\n\
         Result: $Int ::DataType"
    )

    abstract type Ayz <: Component{Int} end
    @xcompfails(
        (@component Kpr{Value} requires(Ayz)),
        :Kpr,
        "Required component: expression does not evaluate \
         to a subtype of '$Component{$Value}', but of '$Component{$Int}':\n\
         Expression: :Ayz\n\
         Result: $Ayz ::DataType"
    )

    @component Wdj{Int}
    @xcompfails(
        (@component Odv{Value} requires(Wdj)),
        :Odv,
        "Required component: expression does not evaluate \
         to a component for '$Value', but for '$Int':\n\
         Expression: :Wdj\n\
         Result: $Wdj ::<$Wdj>"
    )

    # Guard against redundancies.
    abstract type Lpx <: Component{Value} end # (including vertical hierarchy checks)
    @component Rhr <: Lpx
    @component Crq{Value}

    @xcompfails(
        (@component Mpz{Value} requires(Crq, Crq)),
        :Mpz,
        "Requirement <$Crq> is specified twice."
    )

    @xcompfails(
        (@component Mpz{Value} requires(Lpx, Rhr)),
        :Mpz,
        "Requirement <$Rhr> is also specified as $Lpx."
    )

    @xcompfails(
        (@component Mpz{Value} requires(Rhr, Lpx)),
        :Mpz,
        "Requirement <$Rhr> is also specified as $Lpx."
    )

end
end

# ==========================================================================================
module Abstracts
using ..ComponentMacro
using EcologicalNetworksDynamics.Framework
using Main: @sysfails, @pcompfails, @xcompfails
using Test

const S = System{Value}
comps(s) = sort(collect(components(s)); by = repr)

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

@testset "Abstract component types semantics." begin

    # Require an abstract component.
    struct Ahv_b <: Blueprint{Value} end
    @blueprint Ahv_b
    @component Ahv{Value} blueprints(b::Ahv_b) requires(A)
    # It is an error to attempt to expand with no 'A' component.
    @sysfails(S(Ahv_b()), Missing(A, Ahv, [Ahv_b], nothing))
    # But any concrete component is good.
    sb = S(B.b(), Ahv_b())
    sc = S(C.b(), Ahv_b())
    sd = S(D.b(), Ahv_b())
    @test comps(sb) == [Ahv, B]
    @test comps(sc) == [Ahv, C]
    @test comps(sd) == [Ahv, D]
    @test all(has_component.([sb, sc, sd], A))

end
end
end

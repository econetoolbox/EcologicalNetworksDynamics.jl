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

# ==========================================================================================
module Calls

using EcologicalNetworksDynamics: Framework, F
using .Framework

using Test
using Main: @sysfails, @compfails, @failswith

using ..ComponentMacro: Value
const S = System{Value}

comps(s) = collect(F.components(s))
define_component(name, V = Value; kwargs...) = F.define_component(name, V, Calls; kwargs...)

# Testing blueprint collection from module.
# (must be declared at toplevel)
module Plv_b
using ..Calls: Value, F
using .F
struct Ibh_b <: Blueprint{Value} end # Collected.
struct Fek_b <: Blueprint{Value} end # Collected.
struct Zpp_b <: Blueprint{Value} end # Not collected (not exported)
struct Qqu_b <: Blueprint{Int} end # Not collected (not for `Value`).
define_blueprint(Ibh_b)
define_blueprint(Fek_b)
define_blueprint(Zpp_b)
define_blueprint(Qqu_b)
# Not collected.
a = 5
const b = 8
struct Wec end
export Ibh_b, Fek_b, Qqu_b, a, b, Wec
end

module Zru end # Test empty module.

@testset "Calls to `define_component()`." begin

    #---------------------------------------------------------------------------------------
    # Basic, null component.

    define_component(:Eyb)

    # Creation of the singleton type and its instance.
    @test Eyb isa _Eyb
    @test _Eyb <: Component{Value}

    # But there is no blueprint to expand into it.
    @failswith(Eyb(), MethodError)

    #---------------------------------------------------------------------------------------
    # With a basic blueprint.

    # `_b` for the blueprint associated with component `Sem`
    struct Sem_b <: Blueprint{Value} end
    define_blueprint(Sem_b)
    define_component(:Sem; blueprints = [:b => Sem_b])

    # The blueprint is `namespaced` within the component singleton.
    @test Sem.b === Sem_b

    # And we can use it to expand into a component.
    s = System{Value}(Sem.b())
    @test has_component(s, Sem)

    #---------------------------------------------------------------------------------------
    # Require other component.

    struct Cvh_b <: Blueprint{Value} end
    struct Zjz_b <: Blueprint{Value} end
    define_blueprint(Cvh_b)
    define_blueprint(Zjz_b)

    define_component(:Cvh; blueprints = [:b => Cvh_b])
    define_component(:Zjz; blueprints = [:b => Zjz_b], requires = [Cvh])

    @test collect(F.requires(Cvh)) == []
    @test collect(F.requires(Zjz)) == [_Cvh => nothing]

    s = System{Value}()
    # Cannot add Zjz without Cvh.
    @sysfails((s + Zjz.b()), Missing(Cvh, _Zjz, [Zjz_b], nothing))
    s += Cvh.b() # Meet the requirement.
    s += Zjz.b() # Now it's okay.
    @test collect(F.components(s)) == [Cvh, Zjz]

    #---------------------------------------------------------------------------------------
    # Alternate syntax in blocks.

    struct Dsy_b <: Blueprint{Value} end
    struct Lev_b <: Blueprint{Value} end
    define_blueprint(Dsy_b)
    define_blueprint(Lev_b)

    define_component(:Dsy; blueprints = [:b => Dsy_b])
    # Okay to use component *type* instead.
    define_component(:Lev; blueprints = [:b => Lev_b], requires = [_Dsy])

    @test collect(F.requires(Dsy)) == []
    @test collect(F.requires(Lev)) == [_Dsy => nothing]

    s = System{Value}()
    @sysfails((s + Lev.b()), Missing(Dsy, _Lev, [Lev_b], nothing))
    s += Dsy.b() + Lev.b()
    @test collect(F.components(s)) == [Dsy, Lev]

    #---------------------------------------------------------------------------------------
    # Explicit empty lists.

    define_component(:Nzo; blueprints = [], requires = [])
    @test fieldnames(_Nzo) == () # No blueprints listed.
    @test collect(F.requires(Nzo)) == [] # No requirements.

    # Test with a constructible one that it does require nothing.
    struct Lwk_b <: Blueprint{Value} end
    define_blueprint(Lwk_b)
    define_component(:Lwk; blueprints = [:b => Lwk_b], requires = [])
    s = System{Value}(Lwk.b())
    @test has_component(s, Lwk)

    #---------------------------------------------------------------------------------------
    # Basic misuses.

    @compfails(
        define_component(:Vector),
        :Vector,
        "Cannot define component `Vector`: name already defined."
    )

    define_component(:Rrn)
    @compfails(
        define_component(:Rrn),
        :Rrn,
        "Cannot define component `Rrn`: name already defined."
    )

    #---------------------------------------------------------------------------------------
    # Blueprints section.

    @compfails(
        define_component(:Uvv, blueprints = [4 + 5]),
        :Uvv,
        "Not a `name => blueprint` pair: 9 ::$Int",
    )

    @compfails(
        define_component(:Uvv, blueprints = [:b => (4 + 5)]),
        :Uvv,
        "Blueprints list [1]:\n\
         Expected DataType, received instead: 9 ::$Int",
    )

    @compfails(
        define_component(:Uvv, blueprints = [:b => Int]),
        :Uvv,
        "Blueprints list [1]:\n\
        `$Int64` does not subtype `$Blueprint{$Value}`.",
    )

    # The given blueprint(s) need to target the same type.
    struct Uvv_i <: Blueprint{Int} end
    define_blueprint(Uvv_i)
    @compfails(
        define_component(:Uvv, blueprints = [:b => Uvv_i]),
        :Uvv,
        "Blueprints list [1]:\n\
        `$Uvv_i` does not subtype `$Blueprint{$Value}`, but `$Blueprint{$Int}`.",
    )

    # Guard against redundancy / collisions.
    struct Uvv_b <: Blueprint{Value} end
    define_blueprint(Uvv_b)
    @compfails(
        define_component(:Uvv, blueprints = [:b => Uvv_b, :c => Uvv_b]),
        :Uvv,
        "Base blueprint `$Uvv_b` bound to both names :b and :c.",
    )

    struct Uvv_c <: Blueprint{Value} end
    define_blueprint(Uvv_c)
    @compfails(
        define_component(:Uvv, blueprints = [:b => Uvv_b, :b => Uvv_c]),
        :Uvv,
        "Base blueprint :b both refers to `$Uvv_b` and to `$Uvv_c`.",
    )

    struct Yrv_b <: Blueprint{Value} end
    define_blueprint(Yrv_b)
    define_component(:Plv; blueprints = [:b => Yrv_b, Plv_b])

    # Those exported from the module have been added.
    @test fieldnames(_Plv) == (:b, :Ibh_b, :Fek_b) # Missing Zpp and Qqu as expected.
    @test Plv.b == Yrv_b
    @test Plv.Ibh_b == Plv_b.Ibh_b
    @test Plv.Fek_b == Plv_b.Fek_b

    @compfails(
        define_component(:Fyi, blueprints = [Plv_b, :dupe => Plv_b.Fek_b]),
        :Fyi,
        "Base blueprint `$(Plv_b.Fek_b)` bound to both names :Fek_b and :dupe."
    )

    @compfails(
        define_component(:Kxi, blueprints = [Zru]),
        :Kxi,
        "Module `$Zru` exports no blueprint for `$Value`."
    )


    #---------------------------------------------------------------------------------------
    # Requires section.

    @compfails(
        define_component(:Kpr, requires = [4 + 5]),
        :Kpr,
        "Required component:\n\
         Not a component for `$Value`: 9 ::$Int"
    )

    @compfails(
        define_component(:Kpr, requires = [Int]),
        :Kpr,
        "Required component:\n\
         Not a subtype of `$Component`: $Int ::DataType"
    )

    abstract type Ayz <: Component{Int} end
    @compfails(
        define_component(:Kpr, requires = [Ayz]),
        :Kpr,
        "Required component:\n\
         Not a subtype of `$Component{$Value}`, but of `$Component{$Int}`: \
         $Ayz ::$DataType"
    )

    define_component(:Wdj, Int)
    @compfails(
        define_component(:Odv, requires = [Wdj]),
        :Odv,
        "Required component:\n\
         Not a component for `$Value`, but for `$Int`: $Wdj ::<$Wdj>"
    )

    # Guard against redundancies.
    abstract type Lpx <: Component{Value} end # (including vertical hierarchy checks)
    define_component(:Rhr; super = Lpx)
    define_component(:Crq)

    @compfails(
        define_component(:Mpz, requires = [Crq, Crq]),
        :Mpz,
        "Requirement <$Crq> is specified twice."
    )

    @compfails(
        define_component(:Mpz, requires = [Lpx, Rhr]),
        :Mpz,
        "Requirement <$Rhr> is also specified as $Lpx."
    )

    @compfails(
        define_component(:Mpz, requires = [Rhr, Lpx]),
        :Mpz,
        "Requirement <$Rhr> is also specified as $Lpx."
    )

end
end

# ==========================================================================================
module Abstracts

using EcologicalNetworksDynamics: Framework, F
using .Framework

using Test
using Main: @sysfails

using ..ComponentMacro: Value
const S = System{Value}

comps(s) = sort(collect(F.components(s)); by = repr)
define_component(name, V = Value; kwargs...) =
    F.define_component(name, V, Abstracts; kwargs...)

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

@testset "Abstract component types semantics." begin

    # Require an abstract component.
    struct Ahv_b <: Blueprint{Value} end
    define_blueprint(Ahv_b)
    define_component(:Ahv; blueprints = [:b => Ahv_b], requires = [A])
    # It is an error to attempt to expand with no `A` component.
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

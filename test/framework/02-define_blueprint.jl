module Blueprints

using EcologicalNetworksDynamics: Framework, F
using .Framework

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
Base.getproperty(s::System{Value}, name::Symbol) =
    name in fieldnames(System) ? getfield(s, name) : value(s).d[name]

# ==========================================================================================
module Calls

using EcologicalNetworksDynamics: Framework, F
using .Framework

using Test
using Crayons
using Main: @failswith, @sysfails, @bluefails

using ..Blueprints: Value

const S = System{Value}

comps(s) = collect(components(s))
define_component(name, V = Value; kwargs...) = F.define_component(name, V, Calls; kwargs...)

@testset "Calls to define_blueprint()." begin

    # Basic use: empty blueprint.
    struct Gdu_b <: Blueprint{Value} end
    define_blueprint(Gdu_b) # (that's all it takes)

    # Works with a component to expand into.
    define_component(:Gdu; blueprints = [:b => Gdu_b])
    s = System{Value}(Gdu.b())
    @test has_component(s, Gdu)

    # Add a short descriptive string.
    struct Fjr_b <: Blueprint{Value} end
    define_blueprint(Fjr_b, "description for Fjr_b")
    define_component(:Fjr; blueprints = [:b => Fjr_b])
    @test sprint(F.shortline, Fjr_b) == "description for Fjr_b"

    # Add a expansion-time dependency.
    struct Vkl_b <: Blueprint{Value} end
    define_blueprint(Vkl_b)
    define_component(:Vkl; blueprints = [:b => Vkl_b])

    struct Zav_b <: Blueprint{Value} end
    define_blueprint(Zav_b, ""; depends = [Vkl => "Zav likes Vkl"]) # Like for components.
    define_component(:Zav; blueprints = [:b => Zav_b])

    s = System{Value}()
    @sysfails((s + Zav.b()), Missing(Vkl, nothing, [Zav.b], "Zav likes Vkl"))
    s += Vkl.b()
    # Now it's okay.
    s += Zav.b()
    @test has_component(s, Vkl)
    @test has_component(s, Zav)

    # Elide reason.
    struct Ovm_b <: Blueprint{Value} end
    define_blueprint(Ovm_b, ""; depends = [Vkl])
    define_component(:Ovm; blueprints = [:b => Ovm_b])
    @sysfails((System{Value}(Ovm.b())), Missing(Vkl, nothing, [Ovm.b], nothing))

    @bluefails(
        define_blueprint(Vector{Int}),
        Vector{Int},
        "Not a subtype of `$Blueprint`: `Vector{$Int}`."
    )

    struct Xgi end
    @bluefails(define_blueprint(Xgi), Xgi, "Not a subtype of `$Blueprint`: `$Xgi`.")

    abstract type Hek <: Blueprint{Value} end
    @bluefails(
        define_blueprint(Hek),
        Hek,
        "Cannot define blueprint from an abstract type: `$Hek`."
    )

    struct Eap <: Blueprint{Value} end
    define_blueprint(Eap)
    @bluefails(
        define_blueprint(Eap),
        Eap,
        "Type `$Eap` already marked as a blueprint for systems of `$Value`."
    )

end

end

# ==========================================================================================
module Abstracts

using EcologicalNetworksDynamics: Framework, F
using .Framework

using Test
using Crayons
using Main: @failswith, @sysfails, @compfails, @bluefails

using ..Blueprints: Value
const S = System{Value}

comps(s) = sort(collect(components(s)); by = repr)
define_component(name, V = Value; kwargs...) =
    F.define_component(name, V, Abstracts; kwargs...)

@testset "Blueprints imply each other." begin

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

    # An alternate blueprint..
    struct X_b <: Blueprint{Value} end
    define_blueprint(X_b)
    define_component(:X; blueprints = [:b => X_b])
    x = X.b()

    # Indirect implementation to avoid `redefinition warnings` during testing.
    impl = Ref{Any}(nothing)
    F.implied(::X_b) = impl[]

    # .. implies another component.
    impl[] = (_B,) # Concrete component.
    F.implied_blueprint_for(::X_b, ::Type{_B}) = B.b()
    s = S(x)
    @test has_component(s, X)
    @test has_component(s, B)

    impl[] = (A,) # Abstract component.
    F.implied_blueprint_for(::X_b, ::Type{A}) = C.b() # Can have any type.
    s = S(x)
    @test has_component(s, X)
    @test has_component(s, C)

    #---------------------------------------------------------------------------------------
    # Guard component authors against invalid specs.

    # Wrong implied values.
    impl[] = :a
    @sysfails(
        S(x),
        Add(ComponentError, "Not an iterable list of component types: :a ::$Symbol.")
    )
    impl[] = (5,)
    @sysfails(S(x), Add(ComponentError, "Not a component type: 5 ::$Int."))
    impl[] = (B,)
    @sysfails(
        S(x),
        Add(ComponentError, "Not a component type but a component instance: $B.")
    )

    # Forgot to specify implicit constructor.
    impl[] = (_D,)
    @sysfails(
        S(x),
        Add(
            ComponentError,
            "Blueprint $X_b is supposed to imply $_D \
             but the corresponding method is not defined: $F.implied_blueprint_for.",
        )
    )

    # Wrong implicit constructors.
    F.implied_blueprint_for(::X_b, ::Type{_D}) = :a
    @sysfails(
        S(x),
        Add(
            ComponentError,
            "Implicit constructor to implying $_D from $X_b did not yield a blueprint \
             but: :a ::$Symbol.",
        )
    )

    impl[] = (_C,)
    F.implied_blueprint_for(::X_b, ::Type{_C}) = D.b()
    @sysfails(
        S(x),
        Add(
            ComponentError,
            "Blueprint $X_b is supposed to imply a blueprint for $_C, \
             but it implied a blueprint for [$_D] instead.",
        )
    )

end
end
end

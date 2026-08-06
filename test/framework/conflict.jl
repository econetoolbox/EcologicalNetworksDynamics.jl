module ConflictsMacro

# The plain value to wrap in a "system" in subsequent tests.
struct Value end
Base.copy(v::Value) = deepcopy(v)
export Value

# Use submodules to not clash marker names.
# ==========================================================================================
module Calls

using EcologicalNetworksDynamics: Framework
using .Framework

using Test
using Main: @sysfails, @conffails

using ..ConflictsMacro: Value

define_component(name; kwargs...) =
    Framework.define_component(name, Value, Calls; kwargs...)

# Generate many small "markers" components just to toy with'em.
for letter in 'A':'Z'
    C = Symbol(letter)
    Bp = Symbol(C, :_b)
    Bp = eval(quote
        struct $Bp <: Blueprint{Value} end
        define_blueprint($Bp)
        $Bp
    end)
    define_component(C; blueprints = [:b => Bp])
end

@testset "Declaring components conflicts." begin

    #---------------------------------------------------------------------------------------
    # Provide enough data for the declaration to be meaningful.
    @conffails(
        define_conflicts(A),
        "At least two components are required to declare a conflict not only $_A."
    )
    @conffails(
        define_conflicts(A => ()),
        "At least two components are required to declare a conflict not only $_A."
    )
    @conffails((define_conflicts(A, A)), "Component $_A cannot conflict with itself.")
    @conffails((define_conflicts(A, A)), "Component $_A cannot conflict with itself.")

    #---------------------------------------------------------------------------------------
    # No conflicts *a priori*, they are declared by the macro invocation.

    confs(C) = sort(
        collect(Iterators.map(Framework.all_conflicts(typeof(C))) do (a, b, r)
                (Framework.singleton_instance(a), Framework.singleton_instance(b), r)
            end);
        by = repr,
    )
    @test confs(A) == []

    define_conflicts(A, B)
    @test confs(A) == [(A, B, nothing)]
    @test confs(B) == [(B, A, nothing)]

    define_conflicts(C => (), D => ())
    @test confs(C) == [(C, D, nothing)]
    @test confs(D) == [(D, C, nothing)]

    @conffails(
        define_conflicts(4 + 5, 6),
        "First conflicting entry:\n\
         Not a component: 9 ::$Int"
    )

    @conffails(
        define_conflicts(A, 6),
        "Conflicting entry [2]:\n\
         Not a component for `$Value`: 6 ::$Int"
    )

    @conffails(
        define_conflicts(Int, Float64),
        "First conflicting entry:\n\
         Not a subtype of $Component: $Int ::DataType",
    )

    @conffails(
        define_conflicts(A, Float64), # `Value` inferred from the first entry.
        "Conflicting entry [2]:\n\
         Not a subtype of `$Component`: $Float64 ::DataType",
    )

    #---------------------------------------------------------------------------------------
    # Provide a reason for the conflict.

    define_conflicts(C, D => [C => "D dislikes C."])
    @test confs(C) == [(C, D, nothing)]
    @test confs(D) == [(D, C, "D dislikes C.")]

    s = System{Value}(A.b(), C.b())
    @sysfails(
        s + D.b(),
        Add(ConflictWithSystemComponent, _D, nothing, [D.b], _C, nothing, "D dislikes C.")
    )

    # Invalid reasons specs.
    @conffails(
        define_conflicts(E, (4 + 5) => [E => "ok"]),
        "Conflicting entry [2]:\nNot a component for `$Value`: 9 ::$Int",
    )

    @conffails(
        define_conflicts(E, F => [4 + 5]),
        "Reason reference [2, 1]:\nNot a component for `$Value`: 9 ::$Int",
    )

    @conffails(
        define_conflicts(E, F => [E => 4 + 5]),
        "Reason message [2, 1]:\nExpected String, received instead: 9 ::$Int"
    )

    @conffails(
        define_conflicts(E, F => [4 + 5 => "ok"]),
        "Reason reference [2, 1]:\nNot a component for `$Value`: 9 ::$Int",
    )

    @conffails(
        define_conflicts(E, F => [A => "A dislikes F."]),
        "Conflict reason [2, 1] does not refer to a component listed \
         in the same `define_conflicts()` call: $_A => \"A dislikes F.\"."
    )

    @conffails(
        define_conflicts(E, F => [F => "F again?"]),
        "Component $_F cannot conflict with itself."
    )

    @conffails(
        define_conflicts(E, F => [F => "F again?"]),
        "Component $_F cannot conflict with itself."
    )

    @conffails(
        define_conflicts(E, F => [B => "B?"]),
        "Conflict reason [2, 1] does not refer to a component \
         listed in the same `define_conflicts()` call: $_B => \"B?\"."
    )

    # Same, but with a list of reasons.
    @conffails(
        define_conflicts(E, F, G => [F => "ok", E => 4 + 5]),
        "Reason message [3, 2]:\nExpected String, received instead: 9 ::$Int"
    )

    @conffails(
        define_conflicts(E, F, G => [F => "ok", 4 + 5 => "message"]),
        "Reason reference [3, 2]:\nNot a component for `$Value`: 9 ::$Int",
    )

    @conffails(
        define_conflicts(E, F, G => [F => "ok", A => "A dislikes F."]),
        "Conflict reason [3, 2] does not refer to a component listed \
         in the same `define_conflicts()` call: $_A => \"A dislikes F.\"."
    )

    #---------------------------------------------------------------------------------------
    # Even if not all reasons are provided, do declare all conflicts as a clique.

    define_conflicts(
        U,
        V => [X => "V dislikes X.", U => "V dislikes U."],
        W,
        X => [V => "X dislikes V.", W => "X dislikes W."],
        Y => [X => "Y dislikes X."],
        Z,
    )

    # Conflictual with no description of the reason:
    @test confs(U) == [(U, c, nothing) for c in [V, W, X, Y, Z]]
    @test confs(W) == [(W, c, nothing) for c in [U, V, X, Y, Z]]
    @test confs(Z) == [(Z, c, nothing) for c in [U, V, W, X, Y]]
    # Or with a description:
    @test confs(V) == [
        (V, U, "V dislikes U."),
        (V, W, nothing),
        (V, X, "V dislikes X."),
        (V, Y, nothing),
        (V, Z, nothing),
    ]
    @test confs(X) == [
        (X, U, nothing),
        (X, V, "X dislikes V."),
        (X, W, "X dislikes W."),
        (X, Y, nothing),
        (X, Z, nothing),
    ]
    @test confs(Y) == [
        (Y, U, nothing),
        (Y, V, nothing),
        (Y, W, nothing),
        (Y, X, "Y dislikes X."),
        (Y, Z, nothing),
    ]

    # It is okay to imply the same conflicts again in a new invocation..
    define_conflicts(A, U, V => [A => "V dislikes A."]) # (U and V were already known).

    # .. unless it would override the reason already specified.
    @conffails(
        define_conflicts(B, U, V => [U => "New reason why V dislikes U."]),
        "Component $_V already declared to conflict with $_U \
         for the following reason:\n  V dislikes U.",
    )

end
end

# ==========================================================================================
module Abstracts

using EcologicalNetworksDynamics: Framework
using .Framework

using Test
using Main: @sysfails, @conffails

using ..ConflictsMacro: Value
const S = System{Value}

comps(s) = collect(Framework.components(s))
define_component(name; kwargs...) =
    Framework.define_component(name, Value, Abstracts; kwargs...)

@testset "Abstract component conflicts semantics." begin

    # Component type hierachy.
    #
    #    A
    #  ┌─┴─┐      G
    #  B ┌─C─┐  ┌─┼─┐
    #  │ │   │  │ │ │
    #  D E   F  H I J
    #
    abstract type A <: Component{Value} end
    abstract type G <: Component{Value} end
    abstract type B <: A end
    abstract type C <: A end
    struct D_b <: Blueprint{Value} end
    struct E_b <: Blueprint{Value} end
    struct F_b <: Blueprint{Value} end
    struct H_b <: Blueprint{Value} end
    struct I_b <: Blueprint{Value} end
    struct J_b <: Blueprint{Value} end
    define_blueprint(D_b)
    define_blueprint(E_b)
    define_blueprint(F_b)
    define_blueprint(H_b)
    define_blueprint(I_b)
    define_blueprint(J_b)
    define_component(:D; super = B, blueprints = [:b => D_b])
    define_component(:E; super = C, blueprints = [:b => E_b])
    define_component(:F; super = C, blueprints = [:b => F_b])
    define_component(:H; super = G, blueprints = [:b => H_b])
    define_component(:I; super = G, blueprints = [:b => I_b])
    define_component(:J; super = G, blueprints = [:b => J_b])

    # Conflict between abstract and concrete component types.
    define_conflicts(A, H => [A => "H dislikes A."])
    @test comps(S(D.b(), I.b())) == [D, I] #
    @test comps(S(I.b(), D.b())) == [I, D] # (allowed combinations)
    @test comps(S(D.b(), J.b())) == [D, J] #
    @test comps(S(J.b(), D.b())) == [J, D] #
    @sysfails(
        S(D.b(), H.b()), # (with an explicit reason)
        Add(ConflictWithSystemComponent, _H, nothing, [H_b], _D, A, "H dislikes A."),
    )
    @sysfails(
        S(H.b(), D.b()), # (without explicit reason)
        Add(ConflictWithSystemComponent, _D, A, [D_b], H, nothing, nothing),
    )

    # Conflict between two abstract component types.
    define_conflicts(C => [B => "C dislikes B."], B)
    @test comps(S(E.b(), I.b())) == [E, I] #
    @test comps(S(F.b(), I.b())) == [F, I] # (allowed combinations)
    @test comps(S(J.b(), E.b())) == [J, E] #
    @test comps(S(J.b(), F.b())) == [J, F] #
    @sysfails(
        S(D.b(), E.b()), # (with an explicit reason)
        Add(ConflictWithSystemComponent, _E, C, [E_b], _D, B, "C dislikes B."),
    )
    @sysfails(
        S(E.b(), D.b()), # (without explicit reason)
        Add(ConflictWithSystemComponent, _D, B, [D_b], _E, C, nothing),
    )

    # Forbid vertical conflicts.
    @conffails(
        define_conflicts(G, I),
        "Component $_I cannot conflict with its own super-component $G."
    )
    @conffails(
        define_conflicts(I, G),
        "Component $_I cannot conflict with its own super-component $G."
    )

    # Guard against redundant reason specifications.
    @conffails(
        define_conflicts(F, H => [F => "H dislikes F."]),
        "Component $_H already declared to conflict with $_F (as $A) \
         for the following reason:\n  H dislikes A."
    )
    @conffails(
        define_conflicts(D, E => [D => "E dislikes D."]),
        "Component $_E (as $C) already declared to conflict with $_D (as $B) \
         for the following reason:\n  C dislikes B."
    )

    # Conflict with implied components.
    struct Crh_b <: Blueprint{Value} end
    Framework.implied(::Crh_b) = (C,)
    Framework.implied_blueprint_for(::Crh_b, ::Type{C}) = E.b()
    define_blueprint(Crh_b)
    Framework.componentsof(::Crh_b) = (_D,)

    crh = Crh_b()
    @sysfails(
        S(crh),
        Add(ConflictWithBroughtComponent, _D, B, [Crh_b], _E, C, [E.b, Crh_b], nothing)
    )

end
end
end

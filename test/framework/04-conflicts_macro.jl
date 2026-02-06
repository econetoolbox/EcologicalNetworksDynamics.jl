module ConflictsMacro

# The plain value to wrap in a "system" in subsequent tests.
struct Value end
Base.copy(v::Value) = deepcopy(v)
export Value

# Use submodules to not clash marker names.
# ==========================================================================================
module Invocations

using ..ConflictsMacro
using EcologicalNetworksDynamics.Framework

using Test
using Main: @sysfails, @conffails

# Generate many small "markers" components just to toy with'em.
for letter in 'A':'Z'
    C = Symbol(letter)
    Bp = Symbol(C, :_b)
    eval(quote
        struct $Bp <: Blueprint{Value} end
        @blueprint $Bp
        @component $C{Value} blueprints(b::$Bp)
    end)
end

@testset "Declaring components @conflicts." begin

    #---------------------------------------------------------------------------------------
    # Provide enough data for the declaration to be meaningful.
    @conffails((@conflicts), ["No macro arguments provided. Example usage:"])
    @conffails(
        (@conflicts A),
        "At least two components are required to declare a conflict not only :A."
    )
    @conffails(
        (@conflicts(A)),
        "At least two components are required to declare a conflict not only :A."
    )
    @conffails(
        (@conflicts(A,)),
        "At least two components are required to declare a conflict not only :A."
    )
    @conffails(
        (@conflicts (A,)), # Watch this subtle semantic difference.
        "First conflicting entry: expression does not evaluate to a component:\n\
         Expression: :((A,))\n\
         Result: ($A,) ::$Tuple{$(typeof(A))}"
    )
    @conffails(
        (@conflicts(A => ())),
        "At least two components are required to declare a conflict not only :A."
    )
    @conffails((@conflicts(A, A)), "Component $_A cannot conflict with itself.")
    @conffails((@conflicts(A, A)), "Component $_A cannot conflict with itself.")

    #---------------------------------------------------------------------------------------
    # No conflicts *a priori*, they are declared by the macro invocation.

    confs(C) = sort(
        collect(Iterators.map(Framework.all_conflicts(typeof(C))) do (a, b, r)
                (Framework.singleton_instance(a), Framework.singleton_instance(b), r)
            end);
        by = repr,
    )
    @test confs(A) == []

    @conflicts(A, B)
    @test confs(A) == [(A, B, nothing)]
    @test confs(B) == [(B, A, nothing)]

    @conflicts C D
    @test confs(C) == [(C, D, nothing)]
    @test confs(D) == [(D, C, nothing)]

    # Guard against non-components types.
    @conffails(
        (@conflicts(XX, YY)),
        "First conflicting entry: expression does not evaluate: :XX. \
         (See error further down the exception stack.)"
    )

    @conffails(
        (@conflicts(A, YY)),
        "Conflicting entry: expression does not evaluate: :YY. \
         (See error further down the exception stack.)"
    )

    @conffails(
        (@conflicts(4 + 5, 6)),
        "First conflicting entry: expression does not evaluate to a component:\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @conffails(
        (@conflicts(A, 6)),
        "Conflicting entry: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: 6\n\
         Result: 6 ::$Int"
    )

    @conffails(
        (@conflicts(Int, Float64)),
        "First conflicting entry: expression does not evaluate \
         to a subtype of $Component:\n\
         Expression: :Int\n\
         Result: $Int ::DataType",
    )

    @conffails(
        (@conflicts(A, Float64)), # 'Value' inferred from the first entry.
        "Conflicting entry: expression does not evaluate \
         to a subtype of '$Component':\n\
         Expression: :Float64\n\
         Result: $Float64 ::DataType",
    )

    eval(quote
        a = 5 # Must be declared at toplevel for evaluation.
    end)
    @conffails(
        (@conflicts(a, a)),
        "First conflicting entry: expression does not evaluate \
         to a component:\n\
         Expression: :a\n\
         Result: 5 ::$Int",
    )

    @conffails(
        (@conflicts(A, a)),
        "Conflicting entry: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: :a\n\
         Result: 5 ::$Int",
    )

    #---------------------------------------------------------------------------------------
    # Provide a reason for the conflict.

    @conflicts(C, D => (C => "D dislikes C."))
    @test confs(C) == [(C, D, nothing)]
    @test confs(D) == [(D, C, "D dislikes C.")]

    s = System{Value}(A.b(), C.b())
    @sysfails(
        s + D.b(),
        Add(ConflictWithSystemComponent, _D, nothing, [D.b], _C, nothing, "D dislikes C.")
    )

    # Invalid reasons specs.
    @conffails(
        (@conflicts(E, (4 + 5) => (E => "ok"))),
        "Conflicting entry: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int",
    )

    @conffails((@conflicts(E, F => (4 + 5))), "Not a list of conflict reasons: :(4 + 5).")

    @conffails(
        (@conflicts(E, F => (E => 4 + 5))),
        "Reason message: expression does not evaluate to a 'String':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @conffails(
        (@conflicts(E, F => (4 + 5 => "ok"))),
        "Reason reference: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int",
    )

    @conffails(
        (@conflicts(E, F => (A => "A dislikes F."))),
        "Conflict reason does not refer to a component listed \
         in the same @conflicts invocation: $_A => \"A dislikes F.\"."
    )

    @conffails(
        (@conflicts(E, F => (F => "F again?"))),
        "Component $_F cannot conflict with itself."
    )

    @conffails(
        (@conflicts(E, F => (F => "F again?"))),
        "Component $_F cannot conflict with itself."
    )

    @conffails(
        (@conflicts(E, F => (B => "B?"))),
        "Conflict reason does not refer to a component \
         listed in the same @conflicts invocation: $_B => \"B?\"."
    )

    # Same, but with a list of reasons.
    @conffails(
        (@conflicts(E, F, G => (F => "ok", E => 4 + 5))),
        "Reason message: expression does not evaluate to a 'String':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int"
    )

    @conffails(
        (@conflicts(E, F, G => [F => "ok", 4 + 5 => "message"])),
        "Reason reference: expression does not evaluate \
         to a component for '$Value':\n\
         Expression: :(4 + 5)\n\
         Result: 9 ::$Int",
    )

    @conffails(
        (@conflicts(E, F, G => (F => "ok", A => "A dislikes F."))),
        "Conflict reason does not refer to a component listed \
         in the same @conflicts invocation: $_A => \"A dislikes F.\"."
    )

    #---------------------------------------------------------------------------------------
    # Even if not all reasons are provided, do declare all conflicts as a clique.

    @conflicts(
        U,
        V => [X => "V dislikes X.", U => "V dislikes U."],
        W,
        X => (V => "X dislikes V.", W => "X dislikes W."),
        Y => (X => "Y dislikes X."),
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
    @conflicts(A, U, V => (A => "V dislikes A.")) # (U and V were already known).

    # .. unless it would override the reason already specified.
    @conffails(
        (@conflicts(B, U, V => (U => "New reason why V dislikes U."))),
        "Component $_V already declared to conflict with $_U \
         for the following reason:\n  V dislikes U.",
    )

end
end

# ==========================================================================================
module Abstracts

using ..ConflictsMacro
using EcologicalNetworksDynamics.Framework

using Test
using Main: @sysfails, @conffails

const S = System{Value}

comps(s) = collect(components(s))

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
    @blueprint D_b
    @blueprint E_b
    @blueprint F_b
    @blueprint H_b
    @blueprint I_b
    @blueprint J_b
    @component D <: B blueprints(b::D_b)
    @component E <: C blueprints(b::E_b)
    @component F <: C blueprints(b::F_b)
    @component H <: G blueprints(b::H_b)
    @component I <: G blueprints(b::I_b)
    @component J <: G blueprints(b::J_b)

    # Conflict between abstract and concrete component types.
    @conflicts(A, H => (A => "H dislikes A."))
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
    @conflicts(C => (B => "C dislikes B."), B)
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
        @conflicts(G, I),
        "Component $_I cannot conflict with its own super-component $G."
    )
    @conffails(
        @conflicts(I, G),
        "Component $_I cannot conflict with its own super-component $G."
    )

    # Guard against redundant reason specifications.
    @conffails(
        @conflicts(F, H => (F => "H dislikes F.")),
        "Component $_H already declared to conflict with $_F (as $A) \
         for the following reason:\n  H dislikes A."
    )
    @conffails(
        @conflicts(D, E => (D => "E dislikes D.")),
        "Component $_E (as $C) already declared to conflict with $_D (as $B) \
         for the following reason:\n  C dislikes B."
    )

    # Conflict with brought components.
    struct Crh_b <: Blueprint{Value}
        c::Brought(C)
    end
    Framework.implied_blueprint_for(::Crh_b, ::C) = E.b()
    @blueprint Crh_b
    Framework.componentsof(::Crh_b) = (_D,)

    crh = Crh_b(E.b())
    @sysfails(
        S(crh),
        Add(
            ConflictWithBroughtComponent,
            _D,
            B,
            [Crh_b],
            _E,
            C,
            [E.b, false, Crh_b],
            nothing,
        )
    )

    # Or implied.
    crh = Crh_b(E)
    @sysfails(
        S(crh),
        Add(
            ConflictWithBroughtComponent,
            _D,
            B,
            [Crh_b],
            _E,
            C,
            [E.b, true, Crh_b],
            nothing,
        )
    )


end
end
end

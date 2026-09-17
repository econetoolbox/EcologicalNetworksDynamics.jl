# Not exactly sure how to best integrate this (late) feature into the other test files yet.
module Triggers

using EcologicalNetworksDynamics.Framework:
    F, value, Blueprint, Component, System, define_blueprint, add_trigger!

using EcologicalNetworksDynamics.Tests: @argfails
using Test

mutable struct Value
    _vec::Vector{Symbol}
    Value() = new([])
end
Base.copy(v::Value) = deepcopy(v)

define_component(name, V = Value; kwargs...) =
    F.define_component(name, V, Triggers; kwargs...)

@testset "Triggers." begin

    # ======================================================================================
    # Basic uses.

    # (B <: A), (C) and (D)
    abstract type A <: Component{Value} end
    struct B_b <: Blueprint{Value} end
    struct C_b <: Blueprint{Value} end
    struct D_b <: Blueprint{Value} end
    define_blueprint(B_b)
    define_blueprint(C_b)
    define_blueprint(D_b)
    define_component(:B; super = A, blueprints = [:b => B_b])
    define_component(:C; blueprints = [:b => C_b])
    define_component(:D; blueprints = [:b => D_b])

    # Setup triggers.
    ac_trigger(v::Value) = push!(v._vec, :ac)
    ad_trigger(v::Value) = push!(v._vec, :ad)
    bc_trigger(v::Value) = push!(v._vec, :bc)
    bd_trigger(v::Value) = push!(v._vec, :bd)
    add_trigger!([A, C], ac_trigger)
    add_trigger!([A, D], ad_trigger)
    add_trigger!([B, C], bc_trigger)
    add_trigger!([B, D], bd_trigger)

    # Nothing happens without combinations.
    s = System{Value}()
    @test value(s)._vec == []
    s += B.b()
    @test value(s)._vec == []
    @test value(System{Value}(C.b(), D.b()))._vec == []

    # Triggers occur in order they were set.
    s += C.b()
    @test value(s)._vec == [:ac, :bc]

    s += D.b()
    @test value(s)._vec == [:ac, :bc, :ad, :bd]

    # Get a system hook on-demand.
    with_hook(v::Value, ::System) = push!(v._vec, :hook)
    add_trigger!([A, C], with_hook) # Okay to have several triggers.
    @test value(System{Value}(B.b(), C.b()))._vec == [:ac, :hook, :bc] # Still in order.

    # ======================================================================================
    # Invalid uses.

    @argfails(
        add_trigger!([A, A], () -> ()),
        "Component $A specified twice in the same trigger.",
    )

    @argfails(
        add_trigger!([A, B], () -> ()),
        "Both component $_B and its supertype $A specified in the same trigger.",
    )

    fn() = ()
    @argfails(
        add_trigger!([A, D], fn),
        "Missing expected method on the given trigger function: $fn(::$Value).",
    )

    @argfails(
        add_trigger!([A, C], with_hook),
        "Function '$with_hook' already added to triggers for combination {$A, $_C}."
    )


end

end

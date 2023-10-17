# Not exactly sure how to best integrate this (late) feature into the other test files.
# Test it separately.
module Triggers

using EcologicalNetworksDynamics.Framework
const F = Framework
export F
using Main: @argfails
using Test

mutable struct Value
    _vec::Vector{Symbol}
    Value() = new([])
end
Base.copy(v::Value) = deepcopy(v)

@testset "Triggers." begin

    # ======================================================================================
    # Basic uses.

    # (B <: A), (C) and (D)
    abstract type A <: Component{Value} end
    struct B_b <: Blueprint{Value} end
    struct C_b <: Blueprint{Value} end
    struct D_b <: Blueprint{Value} end
    @blueprint B_b
    @blueprint C_b
    @blueprint D_b
    @component B <: A blueprints(b::B_b)
    @component C{Value} blueprints(b::C_b)
    @component D{Value} blueprints(b::D_b)

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
    @test s._value._vec == []
    s += B.b()
    @test s._value._vec == []
    @test System{Value}(C.b(), D.b())._value._vec == []

    # Triggers occur in order they were set.
    s += C.b()
    @test s._value._vec == [:ac, :bc]

    s += D.b()
    @test s._value._vec == [:ac, :bc, :ad, :bd]

    # Get a system hook on-demand.
    with_hook(v::Value, ::System) = push!(v._vec, :hook)
    add_trigger!([A, C], with_hook) # Okay to have several triggers.
    @test System{Value}(B.b(), C.b())._value._vec == [:ac, :hook, :bc] # Still in order.

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

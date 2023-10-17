# Test the system behaviour when correcty setup by framework users.
module RegularUse

using EcologicalNetworksDynamics.Framework
const F = Framework
export F

# The aggregate value to wrap in a "system" in subsequent tests.
# (loosely inspired from a 'dataframe': indexed collection of vectors of same length.
mutable struct Value
    _n::Int64
    _dict::Dict{Symbol,Any}
    Value() = new(0, Dict())
end
Base.copy(v::Value) = deepcopy(v)
# Willing to enjoy wrapped value properties.
Base.getproperty(v::Value, p::Symbol) = Framework.unchecked_getproperty(v, p)
Base.setproperty!(v::Value, p::Symbol, rhs) = Framework.unchecked_setproperty!(v, p, rhs)
export Value

# ==========================================================================================
# Define basic blueprints/components to work with the above value.

module Basics # Use submodules to not clash blueprints/components names.
using ..RegularUse
using .F
using Test
using Main: @sysfails, @failswith
export F, Value

#-------------------------------------------------------------------------------------------
# One component/blueprint for the number of lines.
mutable struct NLines <: Blueprint{Value}
    n::Int64
end
F.early_check(nl::NLines) =
    nl.n > 0 || checkfails("Not a positive number of lines: $(nl.n).")
F.expand!(v, nl::NLines) = (v._n = nl.n)
@blueprint NLines
@component Size{Value} blueprints(N::NLines)
export NLines, Size, _Size

get_n(v::Value) = v._n
@method get_n depends(Size) read_as(n)

#-------------------------------------------------------------------------------------------
# One component to bring 'a' data.
# Various blueprints bring it, gathered within a module.

module ABlueprints # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

using ..Basics
using EcologicalNetworksDynamics.Framework

mutable struct Uniform <: Blueprint{Value}
    value::Float64
end
F.expand!(v, u::Uniform) = (v._dict[:a] = [u.value for _ in 1:v.n])
@blueprint Uniform

mutable struct Raw <: Blueprint{Value}
    a::Vector{Float64}
    size::Brought(Size)
    Raw(a) = new(a, _Size) # Default to implying brought blueprint.
end
F.implied_blueprint_for(r::Raw, ::_Size) = NLines(length(r.a))
function F.late_check(v, raw::Raw)
    na = length(raw.a)
    nv = v.n # <- Use properties there thanks to unchecked_[gs]etproperty(!).
    na == nv || checkfails("Cannot expand $na 'a' values into $nv lines.")
end
F.expand!(v, r::Raw) = (v._dict[:a] = deepcopy(r.a))
@blueprint Raw

end # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The component gathers all blueprints from the above module.
@component begin
    A{Value}
    requires(Size)
    blueprints(Uniform::ABlueprints.Uniform, Raw::ABlueprints.Raw)
end
get_a(v::Value) = v._dict[:a]
@method get_a depends(A) read_as(a)

#-------------------------------------------------------------------------------------------
# One component to bring 'b' data,
# depending on the 'a' data in that all values must be greater than 'a', say.

module BBlueprints # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

using ..Basics
using EcologicalNetworksDynamics.Framework

mutable struct Uniform <: Blueprint{Value}
    value::Float64
end
F.late_check(v, u::Uniform) =
    maximum(v.a) <= u.value || checkfails("Values 'b' not larger than maximum 'a' values.")
F.expand!(v, u::Uniform) = (v._dict[:b] = [u.value for _ in 1:v.n])
@blueprint Uniform

mutable struct Raw <: Blueprint{Value}
    b::Vector{Float64}
    size::Brought(Size)
    Raw(b) = new(b, _Size)
end
function F.late_check(v, raw::Raw)
    nb = length(raw.b)
    nv = v.n
    nb == nv || checkfails("Cannot expand $nb 'a' values into $nv lines.")
    maximum(v.a) <= minimum(raw.b) || checkfails("Values 'b' too small wrt 'a'.")
end
F.expand!(v, r::Raw) = (v._dict[:b] = deepcopy(r.b))
Basics.NLines(r::Raw) = NLines(length(r.b))
F.implied_blueprint_for(r::Raw, ::_Size) = NLines(length(r.b))
@blueprint Raw

end # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

@component begin
    B{Value}
    requires(Size, A)
    blueprints(Uniform::BBlueprints.Uniform, Raw::BBlueprints.Raw)
end
get_b(v::Value) = v._dict[:b]
@method get_b depends(B) read_as(b)

# One method that uses both components.
get_sum(v::Value) = v.a .+ v.b
@method get_sum depends(A, B) read_as(sum)

#-------------------------------------------------------------------------------------------
# One 'marker' component incompatible with others.

struct SparseMark <: Blueprint{Value} end
@blueprint SparseMark
@component Sparse{Value} blueprints(Mark::SparseMark)
@conflicts(Sparse, Size)

#-------------------------------------------------------------------------------------------
# One component whose expansion / checking depends on other components within the system.

struct ReflectionMark <: Blueprint{Value} end
function F.late_check(_, ::ReflectionMark, system)
    if !has_component(system, A) && !has_component(system, B)
        checkfails("Cannot reflect from no data.")
    end
end
function F.expand!(v, ::ReflectionMark, system)
    rf = Char[]
    if has_component(system, A)
        push!(rf, 'A')
    end
    if has_component(system, B)
        push!(rf, 'B')
    end
    rf = collect(Iterators.take(Iterators.cycle(rf), v.n))
    v._dict[:reflection] = rf
end
@blueprint ReflectionMark

# This alternate blueprint
# does not bring data that *don't make sense* without A,
# so it does not *require* A,
# but it needs A to expand.
struct ReflectFromB <: Blueprint{Value} end
function F.expand!(v, ::ReflectFromB)
    v._dict[:reflection] = collect(first.(repr.(Iterators.take(Iterators.cycle(v.a), v.n))))
end
@blueprint ReflectFromB "" depends(A)
@component begin
    Reflection{Value}
    requires(Size)
    blueprints(Mark::ReflectionMark, B::ReflectFromB)
end

# Read property with aliases.
get_reflection(v::Value) = v._dict[:reflection]
@method get_reflection depends(Reflection) read_as(reflection, ref)

# One writeable property.
function set_reflection!(v::Value, rhs::String)
    v._dict[:reflection] = collect(Iterators.take(Iterators.cycle(rhs), v.n))
end
@method set_reflection! depends(Reflection) write_as(reflection, ref)

# ==========================================================================================
# Test actual use of the system.

@testset "Basic components/methods/properties." begin

    # Build empty system.
    s = System{Value}()

    # Add component.
    add!(s, NLines(3))

    # Call method.
    @test get_n(s) == 3

    # Read property (equivalent to the above).
    @test s.n == 3

    # Forbid unexistent properties.
    @sysfails(s.x, Property(x, "Unknown property."))
    # Forbid existent properties without appropriate component.
    @sysfails(s.b, Property(b, "Component $_B is required to read this property."))
    # Same with methods.
    @failswith(get_x(s), UndefVarError => (:get_x, Basics))
    @sysfails(get_b(s), Method(get_b, "Requires component $_B."))

    # Forbid write.
    @sysfails((s.n = 4), Property(n, "This property is read-only."))

    # Cannot add component twice.
    @sysfails(add!(s, NLines(5)), Add(BroughtAlreadyInValue, Size, [NLines]))

    # Add component requiring previous one from a blueprint.
    t = s + A.Uniform(5)
    @test t.a == [5, 5, 5]

    # Fail if custom blueprint constraints are not enforced.
    @sysfails(
        s + A.Raw([5, 5]),
        Add(HookCheckFailure, [A.Raw], "Cannot expand 2 'a' values into 3 lines.", true),
    )

    # Cannot add component if requirement is missing.
    e = System{Value}() # Empty.
    @sysfails(
        e + B.Raw([8, 8, 8]), # Size is brought, but not A.
        Missing(A, B, [B.Raw], nothing),
    )

    # Chain summations.
    s = e + NLines(3) + A.Uniform(5) + B.Uniform(8)

    # Use method/property that requires several components.
    @test s.sum == [13, 13, 13]

    # Cannot add incompatible component.
    @sysfails(
        s + SparseMark(),
        Add(
            ConflictWithSystemComponent,
            Sparse,
            nothing,
            [SparseMark],
            Size,
            nothing,
            nothing,
        ),
    )

    # Blueprint checking may depend on other components.
    r = ReflectionMark()
    s = e + NLines(5)
    @sysfails(
        s + r,
        Add(HookCheckFailure, [ReflectionMark], "Cannot reflect from no data.", true),
    )

    # Blueprint expansion may depend on other components.
    sa = s + A.Uniform(5)
    sb = sa + B.Uniform(8)
    sa += r # Same blueprint..
    sb += r # .. different expansion.
    @test sa.reflection == collect("AAAAA")
    @test sb.reflection == collect("ABABA")

    # Read from aliased properties.
    @test sa.ref == sa.reflection

    # Modify from aliased properties.
    sa.ref = "UVW" # (cycling semantics)
    @test sa.ref == collect("UVWUV")

    # Blueprint expansion may require other components
    # without its component itself requiring them.
    @sysfails(
        s + ReflectFromB(), # .. although reflection does not require B in general.
        Missing(A, nothing, [ReflectFromB], nothing),
    )
    sa = s + A.Raw([1, 2, 3, 2, 1])
    sr = sa + ReflectFromB()
    @test sr.reflection == collect("12321")

    #---------------------------------------------------------------------------------------
    # List properties.

    # All possible system properties and their dependencies.
    props = properties(typeof(sa))
    @test sort(map(((n, r, w, g),) -> (n, r, w, F.singleton_instance.(g)), props)) == [
        (:a, get_a, nothing, Component[A]),
        (:b, get_b, nothing, Component[B]),
        (:n, get_n, nothing, Component[Size]),
        (:ref, get_reflection, set_reflection!, Component[Reflection]),
        (:reflection, get_reflection, set_reflection!, Component[Reflection]),
        (:sum, get_sum, nothing, Component[A, B]),
    ]

    # Only the ones available on this instance.
    props = properties(sa)
    @test sort(collect(props)) == [(:a, get_a, nothing), (:n, get_n, nothing)]

    # Only the ones *missing* on this instance.
    props = latent_properties(sa)
    @test sort(map(((n, r, w, g),) -> (n, r, w, F.singleton_instance.(g)), props)) == [
        (:b, get_b, nothing, Component[B]),
        (:ref, get_reflection, set_reflection!, Component[Reflection]),
        (:reflection, get_reflection, set_reflection!, Component[Reflection]),
        (:sum, get_sum, nothing, Component[B]),
    ]

end

# ==========================================================================================
@testset "Blueprints bring each other: imply/embed." begin

    e = System{Value}() # Empty.

    #---------------------------------------------------------------------------------------
    # Implied blueprints.

    # Implying NLines from A.Raw for Size..
    a = A.Raw([5, 5])
    s = e + a
    @test has_component(s, Size)
    @test has_component(s, A)
    @test s.n == 2

    # Display path to failing brought sub-blueprint in case of failure.
    @sysfails(
        e + A.Raw([]),
        Add(
            HookCheckFailure,
            [NLines, true, A.Raw],
            "Not a positive number of lines: 0.",
            false,
        )
    )

    # Implied blueprint are not expanded if their component is already there.
    s = e + NLines(2)
    s += a # No error.
    @test s.a == [5, 5]

    # But a failure to match is still a failure.
    s = e + NLines(3)
    @sysfails(
        s += a,
        Add(HookCheckFailure, [A.Raw], "Cannot expand 2 'a' values into 3 lines.", true)
    )

    #---------------------------------------------------------------------------------------
    # Embedded blueprints.

    # Explicitly bring it instead of implying.
    a.size = NLines(2)

    # The component is also brought.
    s = e + a
    @test has_component(s, Size)
    @test has_component(s, A)
    @test s.n == 2

    # But the path connection differs in case of failure.
    z = A.Raw([])
    z.size = NLines(0)
    @sysfails(
        e + z,
        Add(
            HookCheckFailure,
            [NLines, false, A.Raw],
            "Not a positive number of lines: 0.",
            false,
        )
    )

    # And it is an error to bring it if the component is already there.
    s = e + NLines(2) # (*even* if the data are consistent)
    @sysfails(s += a, Add(BroughtAlreadyInValue, Size, [NLines, false, A.Raw]))

    #---------------------------------------------------------------------------------------
    # Unbrought blueprints.

    # Alternately: don't bring the blueprint at all.
    a.size = nothing

    # The component is not brought then.
    @sysfails(e + a, Missing(Size, A, [A.Raw], nothing))

end

# ==========================================================================================
@testset "Clone/fork the system by copying it any time." begin

    init = System{Value}()
    s = copy(init)
    @test collect(components(s)) == []
    @test collect(properties(s)) == []

    # Check that the original system is always empty.
    function test_empty(i)
        @test isempty(collect(components(i)))
        @sysfails(get_a(i), Method(get_a, "Requires component $_A."))
        @sysfails(i.a, Property(a, "Component $_A is required to read this property."))
    end
    test_empty(init)

    add!(s, NLines(3), A.Uniform(5))
    @test s.a == [5, 5, 5]
    test_empty(init)

    add!(s, B.Uniform(8), ReflectionMark())
    @test s.b == [8, 8, 8]
    @test s.ref == collect("ABA")
    test_empty(init)

    # Use the + operator to add components without altering the original system.
    a = A.Raw([5, 8, 9])
    s = init + a
    @test s.a == [5, 8, 9]
    test_empty(init)

    # Blueprints must never leak references into the inner system.
    a.a[1] *= 10
    t = init + a
    @test t.a == [50, 8, 9] # Different expansion result in new system.
    @test s.a == [5, 8, 9] # Original system unchanged.
    test_empty(init)

end

end
end

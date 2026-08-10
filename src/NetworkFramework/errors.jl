"""
General exception type for components lib authors and users.
Inherits from `F.InputError` so as to be correctly caught and upgraded
by the component system during `add!`.
"""
abstract type LibError <: F.InputError end

# ==========================================================================================
"Root exception causes, direct input to `throw`."
abstract type RootCause <: LibError end

"""
Raised by component authors on invalid input in extension points.
Automatically upgraded by the framework depending on the context.
"""
struct CheckError <: RootCause
    value::Any # The problematic value within the input.
    mess::String # Explanation.
end
checkerr(v, m::String, throw = Base.throw) = throw(CheckError(v, m))
function Base.showerror(io::IO, e::CheckError)
    (; value, mess) = e
    print(io, mess)
    render_input(io, value)
end

"Raised by this lib when we cannot convert raw input to the desired type."
struct ConvertError <: RootCause
    T::Type # The expected type.
    input::Any
    mess::String
end
converr(T::Type, i, m::String, throw = Base.throw) = throw(ConvertError(T, i, m))
function Base.showerror(io::IO, e::ConvertError)
    (; T, input, mess) = e
    println(io, "Cannot convert inut to `$T`:")
    print(io, mess)
    render_input(io, input)
end

# ==========================================================================================
# Successive upgrading steps from root causes to toplevel exception report.

"A reference into user input."
abstract type InputRef end

"The invalid value is the whole input."
struct WholeInput <: InputRef end
Base.show(::IO, ::WholeInput) = nothing

"Abstract over indices and labels."
const Ref = Union{Int,Symbol}

"One reference to locate invalid value within input."
struct Ref1D <: InputRef
    i::Ref
end
Base.show(::IO, r::Ref1D) = print(io, "[$(repr(r.i))]")

"Two references to locate invalid value within input."
struct Ref2D <: InputRef
    i::Ref
    j::Ref
end
Base.show(::IO, r::Ref1D) = print(io, "[$(repr(r.i)), $(repr(r.j))]")

# Default construct the above.
InputRef(::Tuple{}) = WholeInput()
InputRef((i,)::Tuple{Any}) = Ref1D(i)
InputRef((i, j)::Tuple{Any,Any}) = Ref2D(i, j)
InputRef(i...) = InputRef(i)
InputRef(r::InputRef) = r

"""
Upgrade root cause with a reference to the invalid part of input.
The framework should fill this automatically unless *you*
zare implementing the part where this context is available.
In this case, call `checkerr()` with a reference.
"""
struct RefErr <: F.LibError
    ref::InputRef # Interpreted within *user input*.
    src::RootCause
end
upgrade(s::RootCause, r, rethrow = Base.rethrow) = rethrow(RefErr(InputRef(r), s))
checkerr(r, v, m::String, throw = Base.throw) = upgrade(CheckError(v, m), r, throw)

"""
Upgrade referenced exception with a reference into model data if available and relevant.
Same use as `RefErr`, yet only possible within `late_check` and `mutate!` or `reassign!`.
Most of the time the reference here should be the same as RefErr
because input data and the data stored in the model have the same structure.
This is okay, and the exposed constructor defaults to just copying the reference.
"""
struct ModelRefErr <: F.LibError
    mref::Union{InputRef} # Intepreted within *model data*. Nothing if irrelevant.
    src::RefErr
end
upgrade(s::RefErr, r, rethrow = Base.rethrow) = rethrow(ModelRefErr(InputRef(r), s))
function checkerr(::Model, r, v, m::String, throw = Base.throw)
    ref = InputRef(r)
    chk = CheckError(v, m)
    rfr = RefErr(ref, chk)
    upgrade(rfr, ref, throw)
end

# ==========================================================================================
"""
Final upgrade of model-referenced exception into a blueprint failure report.
This should be done automatically by the framework without component authors noticing.
"""
struct BlueprintError <: F.LibError
    B::Type{<:Blueprint}
    step::Symbol # Failed operation (exposed pipeline step).
    model::Option{Model} # If available (not before :late_check).
    src::ModelRefErr
end

function Base.showerror(io::IO, e::BlueprintError)
    (; B, step, model, src) = e
    (; ref, src) = src
    (; mref, src) = src
    d = D.dispatcher(B)
    B = "blueprint $B"
    doing = if step == :construct
        "constructing $B"
    elseif step == :early
        "verifying $B"
    elseif step == :late
        "verifying $B against model"
    else
        "<performing step $(repr(step)) with blueprint $B \
         $black(display bug, please report)$reset>"
    end
    println(io, "While $doing:")
    print(io, "In the provided value")
    if !(ref isa WholeInput)
        print(io, " at $ref")
    end
    if isnothing(mref)
        println(io, ":")
    else
        mv = modelvalue(d, mref, model)
        println(io, " that would become $mv:")
    end
    showerror(io, src)
end

# ==========================================================================================
"""
Raise if we cannot interpret raw input as an index into model data.
Not supposed to be raised by component authors because index checking is implemented here.
"""
abstract type IndexError <: LibError end

# ==========================================================================================
"""
Final upgrade of model-referenced exception into a mutation failure report.
This should be done automatically by the framework without component authors noticing.
"""
struct MutationError <: F.LibError
    d::D.AbstractField
    step::Symbol # Failed operation (:mutate or :assign).
    model::Model # Always available.
    src::ModelRefErr # mref cannot be `nothing`.
end

function Base.showerror(io::IO, e::MutationError)
    (; d, step, model, src) = e
    (; ref, src) = src
    (; mref, src) = src
    f = D.field(d)
    changing = if step == :mutate
        "mutating"
    elseif step == :early
        "assigning"
    else
        "<performing $(repr(step)) $black(display bug, please report)$reset>"
    end
    mv = modelvalue(d, mref, model)
    println(io, "While $changing $f $mv:")
    print(io, "In the provided value")
    if !(ref isa WholeInput)
        print(io, " at $ref")
    end
    println(io, ":")
    showerror(io, src)
end

modelvalue(d::D.GraphField, ::WholeInput, ::Model) = "model $d value for the network"
modelvalue(d::D.Class, r::Ref1D, ::Model) = "model $d name for node $r"
modelvalue(d::D.Web, r::Ref2D, ::Model) = "model $d topology for edge $r"
function modelvalue(d::D.NodeField, r::Ref1D, m::Model)
    f, c = D.field(d), D.class(d)
    n = N.network(m)
    id = N.index(n, c)
    i, l = N.to_index(id, r.i), N.to_label(id, r.i)
    "model $d node value $f[$i] ($(repr(l)))"
end
function modelvalue(d::D.EdgeField, r::Ref2D, m::Model)
    f, (s, t) = D.field(d), d |> D.web |> D.sidenames
    n = N.network(m)
    src, tgt = N.index.((n,), (s, t))
    (i, j), (a, b) = N.to_index.((src,), (r.i, r.j)), N.to_label.((tgt,), (r.i, r.j))
    "model $d edge value $f[$i, $j] ($(repr(a)), $(repr(b)))"
end

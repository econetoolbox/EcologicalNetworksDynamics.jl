"""
General exception type for components lib authors and users.
Inherits from `F.InputError` so as to be correctly caught and upgraded
by the component system during `add!`.
"""
abstract type LibError <: F.InputError end

"""
Generic report content.
"Upgrading" the report with additional context
first referst to filling out the later fields if meaningful as the exception bubbles up.
The last stage of upgrading is wrapping the report within a dedicated error type.
As in: the report should *not* bubble up to the REPL on its own.
"""
mutable struct CheckError <: LibError
    """
    Root cause.
    Should be focused and simple to write by component authors,
    trusting that external context will be filled up by the framework,
    unless they are hooking higher in the usual call chain.
    """
    mess::String
    """
    The problematic value to be reported.
    Either directly taken from user input or from lowered data.
    """
    value::Any
    "The kind of data being reported."
    d::Dispatcher
    "User input reference: Locate the value within total user input."
    uref::Any
    """
    Model reference: if relevant, locate the associated value within the focal model.
    Similar to user input reference, but actually orthogonal because *e.g.* in
    value[4:6] = [1, 2, 3]
    , the 2nd user input value actually corresponds to the 5th model data value.
    """
    mref::Option{Any}
    CheckError(mess::String, value, d::Dispatcher) =
        CheckError(mess, value, d, WholeData(), nothing)
end

"Exposed entrypoint to component authors, to issue a bubbling report"
checkerr(d::Dispatcher, value, mess::String, throw = Base.throw) =
    throw(CheckError(mess, value, d))

#-------------------------------------------------------------------------------------------
# User/model input references.

"The invalid value is the whole data."
struct WholeData end

"Abstract over indices and labels."
const URef = Union{Int,Symbol}
print_uref(uref) = sprint(print_uref, uref)
print_uref(io::IO, (i,)::Tuple{URef}) = print(io, "[$(repr(i))]")
print_uref(io::IO, (i, j)::Tuple{R,R}) where R<:URef =
    print(io, "[$(repr(i)), $(repr(j))]")

"Refer to *both* node index and label."
const MRef = Tuple{Int,Symbol}
print_mref(mref) = sprint(print_mref, mref)
print_mref(io::IO, ((i, a),)::Tuple{MRef}) = print(io, "[$i] ($(repr(a)))")
print_mref(io::IO, ((i, a), (j, b))::Tuple{MRef,MRef}) =
    print(io, "[$i, $j] ($(repr(a)), $(repr(b)))")

#-------------------------------------------------------------------------------------------
# Display.

function Base.showerror(io::IO, e::CheckError)
    (; mess, value, d, uref, mref) = e
    print(io, "In the provided input")
    if !(uref isa WholeData)
        print(io, " at ")
        print_uref(io, uref)
    end
    if isnothing(mref)
        print(io, ":\n")
    else
        mv = modelvalue(d, mref)
        print(io, isnothing(uref) ? " " : "\n")
        print(io, "which would become $mv:\n")
    end
    print(io, mess)
    render_input(io, value)
end

modelvalue(d::D.GraphField, ::WholeData) = "model $d value for the network"
modelvalue(d::D.Class, mref) = "model $d name for node " * print_mref(mref)
modelvalue(d::D.Web, mref) = "model $d topology for edge " * print_mref(mref)
modelvalue(d::D.NodeField, mref) =
    "model $d node value " * String(D.field(d)) * print_mref(mref)
modelvalue(d::D.EdgeField, mref) =
    "model $d edge value " * String(D.field(d)) * print_mref(mref)

# ==========================================================================================
"""
Final upgrade of model-referenced exception into a blueprint failure report.
This should be done automatically by the framework without component authors noticing.
"""
struct BlueprintError <: LibError
    B::Type{<:Blueprint}
    step::Symbol # Failed operation (exposed pipeline step).
    src::CheckError
end

function Base.showerror(io::IO, e::BlueprintError)
    (; B, step, src) = e
    doing = if step == :construct
        "constructing blueprint " * F.bpdisplay(B; color = true)
    elseif step == :early
        "verifying blueprint"
    elseif step == :late
        "verifying blueprint against model"
    else
        "<performing step $(repr(step)) with blueprint $B \
         $black(display bug, please report)$reset>"
    end
    println(io, "While $doing:")
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
struct MutationError <: LibError
    d::D.AbstractField
    step::Symbol # Failed operation (:mutate or :assign).
    src::CheckError
end

function Base.showerror(io::IO, e::MutationError)
    (; d, step, model, src) = e
    (; mref, src) = src
    (; ref, src) = src
    changing = if step == :mutate
        "mutating"
    elseif step == :assign
        "assigning to"
    else
        "<performing $(repr(step)) $black(display bug, please report)$reset>"
    end
    mv = modelvalue(d, mref)
    println(io, "While $changing $mv:")
    if !(ref isa WholeData)
        print(io, "In the provided value at $ref:")
    end
    showerror(io, src)
end

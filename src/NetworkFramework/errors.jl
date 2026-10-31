"""
General exception type for components lib authors and users.
Inherits from `F.InputError` so as to be correctly caught and upgraded
by the component system during `add!`.
Upgrades should be done by the framework by default,
so that component authors should not have to worry about it
unless they write very singular components.
"""
abstract type LibError <: F.InputError end

"Reference into problematic user input."
abstract type InputRef end

#-------------------------------------------------------------------------------------------

"""
Report problematic value within user input,
either meant to become *data* within the model or to *query* it.
"Upgrading" the report with additional context
first refers to filling out contextual fields
later if meaningful as the exception bubbles up.
The last stage of upgrading is wrapping the report within a contextualized error type.
"""
mutable struct CheckError <: LibError
    """
    The kind of data being reported.
    Unknown when emitted from an independent default impl.
    """
    d::Option{Dispatcher}
    """
    The problematic value to be reported.
    Either directly taken from user input or from lowered data.
    """
    value::Any
    """
    Reference the problematic value within user input.
    Either a 'user reference', attempting to reference it within raw input
    (if emitted during construction, conversion, early_check)
    or a 'model reference', mapping it to underlying model data
    (if emitted during late_check).
    Make sure not to confuse the two. For instance in:

        value[4:6] = [1, 2, 3]

    the 2nd user input value corresponds to the 5th model data value.
    When a 'model reference', report both index and label.
    Reporting both unfortunately requires carrying too much context
    from `convert` to `late_check` and makes the code too complicated.
    Would be nice to find an easy way though.
    """
    ref::InputRef
    """
    Root cause.
    Should be focused and simple to write by component authors,
    trusting that external context will be filled up by the framework,
    unless they are hooking higher in the usual call chain.
    """
    mess::String
    CheckError(
        value,
        mess::String;
        d = nothing,
        ref = UserRef(WholeData),
    ) = new(d, value, ref, mess)
end
"Upgrade underlying errors."
CheckError(e::CheckError) = e

"Exposed entrypoint to issue a bubbling report"
checkerr(value, mess::String, throw = Base.throw; kwargs...) =
    throw(CheckError(value, mess; kwargs...))

#-------------------------------------------------------------------------------------------
# User/model input references.

"""
Reference within raw user input.
- `(q,)` refers to 1-dimensional index or label `q` within user input.
- `(q, r)` refers to 2-dimensional indices or labels within user input.
"""

struct UserRef{T} <: InputRef
    ref::T
    UserRef(ref::T) where T = new{T}(ref)
end

"""
Reference to input data mapped within model data,
typically using both indices and labels: `((i, a),)` or `((i, a), (j, b))`.
"""
struct ModelRef{T} <: InputRef
    ref::T
    ModelRef(ref::T) where T = new{T}(ref)
end

"The invalid value targets all corresponding inner model data."
struct _WholeData end
const WholeData = _WholeData()

"Abstract over indices and labels."
const Ref = Union{Int,Symbol}
print_ref(uref) = sprint(print_ref, uref)
function print_ref(io::IO, uref::UserRef{<:Tuple{Ref}})
    (i,) = uref.ref
    print(io, "[$(repr(i))]")
end
function print_ref(io::IO, uref::UserRef{<:Tuple{Ref,Ref}})
    (i, j) = uref.ref
    print(io, "[$(repr(i)), $(repr(j))]")
end

"Refer to *both* node index and label."
const MRef = Tuple{Int,Symbol}
function print_ref(io::IO, mref::ModelRef{Tuple{MRef}})
    ((i, a),) = mref.ref
    print(io, "[$i] ($(repr(a)))")
end
function print_ref(io::IO, mref::ModelRef{Tuple{MRef,MRef}})
    ((i, a), (j, b)) = mref.ref
    print(io, "[$i, $j] ($(repr(a)), $(repr(b)))")
end
function print_ref(io::IO, mref::ModelRef{Tuple{SparseVector{Bool}}})
    mask = mref.ref
    print(io, "[<$(join_elided(collect(I.map(Int, mask)), ""))>]")
end
function print_ref(io::IO, mref::ModelRef{Tuple})
    (; ref) = mref
    print(io, "[$(join_elided(ref, ", "))]")
end

"Upgrade from either to both."
to_mref(uref::Ref, ix::N.Index) = (N.to_index(ix, uref), N.to_label(ix, uref))
to_mref((i,)::Tuple{Ref}, md::Model, d::D.NodeLevel) =
    ModelRef((to_mref(i, N.class(md, d).index),))
to_mref((i, j)::Tuple{Ref,Ref}, md::Model, d::D.EdgeLevel) =
    ModelRef(to_mref.((i, j), map(cl -> cl.index, N.sides(md, d))))
to_mref(::_WholeData, ::Model, ::Dispatcher) = ModelRef(WholeData)

"Upgrade underlying error with outer uref context."
urefguard(fn::Function, uref) =
    try
        fn()
    catch e
        e isa CheckError || rethrow(e)
        if e.ref isa UserRef{_WholeData}
            e.ref = UserRef(uref)
        end
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Display.

function Base.showerror(io::IO, e::CheckError)
    (; mess, value, d, ref) = e
    at(::Union{UserRef{_WholeData},ModelRef}) = "" # (reported as mref then)
    at(uref) = " at " * print_ref(uref)
    targetting(::Nothing, _) = ""
    targetting(_, ::UserRef) = ""
    targetting(::Nothing, ::UserRef) = ""
    targetting(d::Dispatcher, mref::ModelRef) = " targetting " * modelvalue(d, mref)
    for_d(::Nothing) = ""
    for_d(d) = " for $d"
    skip = isnothing(d) && ref.ref == WholeData # Uninformative line then.
    skip || println(io, "In the provided input$(at(ref))$(targetting(d, ref))$(for_d(d)):")
    println(io, mess)
    render_input(io, value)
end

modelvalue(::Nothing, mref) = print_ref(mref)
modelvalue(::D.GraphField, ::ModelRef{_WholeData}) = "network value"
modelvalue(::D.Class, ::ModelRef{_WholeData}) = "node values"
modelvalue(::D.Web, ::ModelRef{_WholeData}) = "edge values"
modelvalue(::D.Class, mref) = "name for node " * print_ref(mref)
modelvalue(::D.Web, mref) = "topology for edge " * print_ref(mref)
function modelvalue(d::D.AbstractField, mref)
    level = D.level(d)
    mr = print_ref(mref)
    s = plural(mref)
    "$level value$s $mr"
end
plural(::Any) = "(s)"
plural(::Tuple{MRef}) = ""
plural((r,)::Tuple{UnitRange}) = ns(length(r))[2]

# ==========================================================================================

"Contextualize failure within the pipeline bringing new data to the model."
struct BlueprintError <: LibError
    "Data is appended using blueprints. This is the associated blueprint type."
    B::Type{<:Blueprint}
    "Failed pipeline step, among (:construct, :early, :late)."
    step::Symbol
    "Underlying report."
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

"Contextualize failure within the pipeline modifying the model data."
struct MutationError <: LibError
    src::CheckError
end

function Base.showerror(io::IO, e::MutationError)
    (; src) = e
    println(io, "While mutating model:")
    showerror(io, src)
end

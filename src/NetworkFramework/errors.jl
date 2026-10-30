"""
General exception type for components lib authors and users.
Inherits from `F.InputError` so as to be correctly caught and upgraded
by the component system during `add!`.
Upgrades should be done by the framework by default,
so that component authors should not have to worry about it
unless they write very singular components.
"""
abstract type LibError <: F.InputError end

#-------------------------------------------------------------------------------------------

"""
Report problematic value within user input,
either meant to become *data* within the model or to *query* it.
"Upgrading" the report with additional context
first refers to filling out the later fields if meaningful as the exception bubbles up.
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
    "User input reference: Locate the value within total user input."
    uref::Any
    """
    Model reference: if relevant, locate the associated value within the focal model.
    Similar to user input reference, but actually orthogonal because *e.g.* in

        value[4:6] = [1, 2, 3]

    , the 2nd user input value actually corresponds to the 5th model data value.
    """
    mref::Option{Any}
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
        uref = WholeData,
        mref = nothing,
    ) = new(d, value, uref, mref, mess)
end
"Upgrade underlying errors."
CheckError(e::CheckError) = e

"Exposed entrypoint to issue a bubbling report"
checkerr(value, mess::String, throw = Base.throw; kwargs...) =
    throw(CheckError(value, mess; kwargs...))

#-------------------------------------------------------------------------------------------
# User/model input references.

"The invalid value is the whole data."
struct _WholeData end
const WholeData = _WholeData()

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
print_mref(io::IO, (mask,)::Tuple{SparseVector{Bool}}) =
    print(io, "[<$(join_elided(collect(I.map(Int, mask)), ""))>]")
print_mref(io::IO, mref::Tuple) = print(io, "[$(join_elided(mref, ", "))]")

"Upgrade from either to both."
complete_mref(uref::URef, ix::N.Index) = (N.to_index(ix, uref), N.to_label(ix, uref))
complete_mref((uref,)::Tuple{URef}, md::Model, d::D.NodeLevel) =
    (complete_mref(uref, N.class(md, d).index),)
complete_mref(uref::Tuple{URef,URef}, md::Model, d::D.EdgeLevel) =
    complete_mref.(uref, map(cl -> cl.index, N.sides(md, d)))
complete_mref(::_WholeData, ::Model, ::Dispatcher) = WholeData

"Aggregate references as the report bubble up."
nestref(n, uref) = (n, uref)
nestref(n, ::_WholeData) = (n,)
"Upgrade underlying error with outer uref context."
urefguard(fn::Function, uref) =
    try
        fn()
    catch e
        e isa CheckError || rethrow(e)
        e.uref = nestref(uref, e.uref)
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Display.

function Base.showerror(io::IO, e::CheckError)
    (; mess, value, d, uref, mref) = e
    Inthat = "In the provided input"
    openline = if uref == WholeData
        if !isnothing(d)
            print(io, "$Inthat for $d")
            true
        else
            false
        end
    else
        print(io, "$Inthat at ")
        print_uref(io, uref)
        true
    end
    if irrelevant_mref(mref, uref)
        if openline
            println(io, ":")
        end
    else
        if !openline
            print(io, Inthat)
        end
        mv = modelvalue(d, mref)
        println(io, " targetting $mv:")
    end
    println(io, mess)
    render_input(io, value)
end

"True if printing `mref` does not bring more information w.r.t `uref`."
irrelevant_mref(mref, uref) =
    if isnothing(mref)
        true
    elseif mref === WholeData
        true
    elseif uref === WholeData
        mref === WholeData
    else
        false
    end

modelvalue(d::D.GraphField, ::_WholeData) = "$d value"
modelvalue(d::D.Class, mref) = "$d name for node " * print_mref(mref)
modelvalue(d::D.Web, mref) = "$d topology for edge " * print_mref(mref)
function modelvalue(d::D.AbstractField, mref)
    level = D.level(d)
    mr = print_mref(mref)
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

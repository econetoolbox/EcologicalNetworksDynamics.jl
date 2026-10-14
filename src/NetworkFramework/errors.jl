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
# Display.

Base.showerror(io::IO, e::CheckError) = render(io, e)
function render(io::IO, e::CheckError; what = "input", display_input = true)
    (; mess, value, d, uref, mref) = e
    print(io, "In the provided $what")
    if !(uref isa WholeData)
        print(io, " at ")
        print_uref(io, uref)
    end
    irrelevant_mref = if isnothing(mref)
        true
    elseif uref isa WholeData
        mref isa WholeData
    elseif uref isa Tuple{Vararg{Int}}
        uref == getindex.(mref, 1)
    elseif uref isa Tuple{Vararg{Symbol}}
        uref == getindex.(mref, 2)
    else
        true
    end
    if irrelevant_mref
        print(io, ":\n")
    else
        mv = modelvalue(d, mref)
        print(io, isnothing(uref) ? " " : "\n")
        print(io, "referring to inner $mv:\n")
    end
    print(io, mess)
    if display_input
        render_input(io, value)
    end
end

modelvalue(d::D.GraphField, ::WholeData) = "model $d value for the network"
modelvalue(d::D.Class, mref) = "model $d name for node " * print_mref(mref)
modelvalue(d::D.Web, mref) = "model $d topology for edge " * print_mref(mref)
function modelvalue(d::D.AbstractField, mref)
    (name, field), level = D.content(d), D.level(d)
    mr = print_mref(mref)
    "model $(repr(name)) $level value $(repr(field)) $mr"
end

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

"Contextualize failure within input meant to *query* data within the model."
mutable struct QueryError <: LibError
    "The total, initial query *e.g.* typical arguments to julia indexing syntax `[...]`."
    query::Tuple
    "For now, all queries are made through `views`. This is the corresponding view type."
    View::Type # (Note: this would move to a super-error if querying exists without views.)
    "Underlying report."
    src::CheckError
end

function Base.showerror(io::IO, e::QueryError)
    (; View, query, src) = e
    d = dispatcher(View)
    println(io, "View error ($(V.type_info(View))):")
    report() = NF.render(io, src; what = "query", display_input = false)
    # Report either before or after depending on the query size.
    if length(repr(query)) <= 20
        # Easier to understand before..
        q = "[" * join_elided(query, ", ") * "]"
        println(io, "Cannot index with $q into $d:")
        report()
    else
        # .. unless the query would flood the report.
        report()
        if src.value != query
            println(io, "Cannot index into $d with: [")
            for q in query
                render_input(
                    io,
                    q,
                    (short, Q) -> "  $short ::$Q,\n",
                    (long, Q) -> begin
                        print(io, "  ")
                        long()
                        print(io, "  ::$Q,\n")
                    end,
                )
            end
        end
        print(io, "]")
    end
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

"""
Testing utils.
Not useful for end users, but heavily used in package automated testing
and useful to setup development environment with Revise for contributors.
"""
module Tests

"""
Edit quoted macrocall with the given location.
Useful when generating `@test` calls from within `@test_*` macro
but we want failures to point to the latter, not the former.
"""
function liftmcall(xp, src)
    xp.head == :macrocall || throw("Not a macrocall to be lifted: $xp.")
    xp.args[2] = src
    xp
end

include("./strings.jl")
include("./errors.jl")

# ==========================================================================================
# Exposed testing interface, with the collection of macros directly used in tests.

const T = Tests

using EcologicalNetworksDynamics:
    EN, N, F, NF, D, I, SparseMatrix, Display, errwith, withcontext, prepend_context!,
    OneShotReport
using .Display: rept, render_input, yellow, black, reset, italics

using .Strings:
    showcompare,
    is_string, is_repr, is_disp,
    check_string, check_repr, check_disp, check_err,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors: @fails, @fails_with, @genfailsmacro, FieldsCompare, WrongField

using Test

"""
Numerous exception types in the package have a `mess` field
to be tested as an error message.
"""
const mess = FieldsCompare.message

# Native julia exceptions.
@genfailsmacro errfails Base.ErrorException (; msg = mess)
@genfailsmacro argfails Base.ArgumentError (; msg = mess)
@genfailsmacro jl_deffails Base.UndefVarError (; world = nothing)
@genfailsmacro jl_callfails Base.MethodError (; world = nothing)

# Network errors.
@genfailsmacro netfails EN.Networks.NetworkError
@genfailsmacro labelfails EN.Networks.LabelError (; index = nothing)

# API utils errors.
@genfailsmacro aliasfails EN.AliasingDicts.AliasError (; mess)

#-------------------------------------------------------------------------------------------
# Framework errors.

@genfailsmacro propfails F.PropertyError (; mess)
@genfailsmacro callfails F.MethodCallError (; mess)
@genfailsmacro conflfails F.ConflictError (; mess)

"Generate macros for failures in defining items."
macro genitemfailsfor(itemtype, name)
    itemtype = QuoteNode(itemtype)
    quote
        macro $name(xp, f...)
            src = $(esc(:__source__)) # (https://github.com/JuliaLang/julia/issues/62572)
            liftmcall(:($($T).@itemfails($xp, $($itemtype), $(f...))), src) |> esc
        end
    end
end
@genfailsmacro itemfails F.ItemError (; mess)
@genitemfailsfor :blueprint bluefails
@genitemfailsfor :component compfails
@genitemfailsfor :method methfails

"Test various possible failures during `Framework.add!()`."
module addfails
    using ..T: T, I, F, @genfailsmacro, mess, rept
    "The `node` fields on `AddError` is easily tested as a *path* of blueprint types."
    function node(exp, node)
        exp isa Vector ||
            T.errwith("not a path vector to compare against a node", rethrow) do io
                println(io, rept(exp))
            end
        node isa F.Node || T.errwith(T.WrongField, "not an `add!` node", rethrow) do io
            println(io, rept(node))
        end
        act = []
        while !isnothing(node)
            push!(act, typeof(node.blueprint))
            node = node.parent
        end
        err() = T.errwith(T.WrongField, "wrong nodes path", rethrow) do io
            T.showcompare(io, repr.(exp), repr.(act))
        end
        length(act) == length(exp) || err()
        for (e, a) in zip(exp, act)
            e === a || err()
        end
    end
    @genfailsmacro bpconflict F.ConflictWithBroughtComponent (; node, other_node = node)
    @genfailsmacro broughtalready F.BroughtAlreadyInValue (; node)
    @genfailsmacro component F.ComponentError (; mess)
    @genfailsmacro check F.HookCheckFailure (; node, mess)
    @genfailsmacro lower F.LoweringAborted (; node)
    @genfailsmacro missingrequired F.MissingRequiredComponent (; node)
    @genfailsmacro sysconflict F.ConflictWithSystemComponent (; node)
end

#-------------------------------------------------------------------------------------------
raw"""
Exposed library errors.
These are sophisticated, nested error types.
Only macros testing toplevel reports are generated.
Here is how to use them:

  @bpfails(     <- Expect NF.BlueprintError.
    xp,         <- The expression tested.
    B, step, m, <- The regular exception fields.
    (           <- Recurse into nested exceptions. No need to test their (fixed) types.
      mref,     <- Expected subfield.
      ref,      <- Expected sub-subfield, although no need to nest more!
      :root,    <- Target expectetdj NF.RootCause type with a short name.
      ...       <- Subsequent fields are those of the rootcause type.
    ),
  )

"""
function test_mref(exp, act::NF.ModelRefErr)
    exp isa Tuple ||
        errwith("Not a tuple to compare against nested error:", rethrow) do io
            render_input(io, exp)
        end
    if length(exp) < 4
        errwith("Not enough expected nested fields values to test:", rethrow) do io
            showcompare(io, "(mref, ref, root, root_fields...)", exp)
        end
    end
    a, b, c, d... = exp
    exp = (; mref = a, ref = b, root = c, fields = d)
    withcontext(WrongField, compare_refs, exp.mref, act.mref) do io
        println(io, "Reported model reference $(black).mref$reset:")
    end
    withcontext(WrongField, compare_refs, exp.ref, act.src.ref) do io
        println(io, "Reported input reference $(black).ref$reset:")
    end
    withcontext(WrongField, FieldsCompare.type, :root, exp.root) do io
        println(io, "Reported root cause type:")
    end
    # Translate to expected root error type.
    dict = (; check = NF.CheckError, convert = NF.ConvertError)
    R = if haskey(dict, exp.root)
        dict[exp.root]
    else
        errwith("Unknown possible root cause type:", rethrow) do io
            showcompare(io, "one among: $(keys(dict))", exp.root)
        end
    end
    # Then reuse former utils to check the root error as usual.
    act_root = act.src.src
    enames = fieldnames(R)
    err = try
        Errors.check_expected_fields(R, enames, exp.fields)
        act_root isa R || Errors.unexpected_error_type(act_root, R, exp.fields)
        Errors.test_error_expected(act_root, R, enames, exp.fields, (;))
        nothing
    catch e
        e isa OneShotReport || rethrow(e)
        e # Exit that nested block to avoid cluttering output with original error.
    end
    isnothing(err) || rethrow(
        prepend_context!(err) do io
            println(io,
                "When testing underlying root cause \
                 $yellow$(repr(exp.root))$reset:")
        end,
    )
end

"Test `$(NF.InputRef)` value, using `:whole` to expect `$(NF.WholeInput)`."
compare_refs(::Nothing, ::Nothing) = @test true
compare_refs(exp, act::NF.InputRef) = FieldsCompare.default(exp, act)
compare_refs(exp::Symbol, ::NF.WholeInput) =
    if exp == :whole
        @test true
    else
        errwith(WrongField, "wrong input reference", rethrow) do io
            showcompare(
                io,
                exp,
                ":whole $italics(alias for $black$(NF.WholeInput)$reset$italics)$reset",
            )
        end
    end

"Test datakind/dispatcher value, using tuples of symbols for their content."
test_datakind(exp, ::D.Dispatcher) =
    errwith("Not a tuple of symbols to compare against data kind:", rethrow) do io
        showcompare(io, "data kind spec like (:class, :field)", exp)
    end
test_datakind(exp::Tuple{Vararg{Symbol}}, act::D.Dispatcher) =
    FieldsCompare.value(exp, D.content(act))

@genfailsmacro bpfails EN.NetworkFramework.BlueprintError (; src = test_mref)
@genfailsmacro mutfails EN.NetworkFramework.MutationError (;
    d = test_datakind,
    src = test_mref,
)

#-------------------------------------------------------------------------------------------
# (reassure JuliaLS)

macro aliasfails end
macro argfails end
macro bluefails end
macro bpfails end
macro callfails end
macro compfails end
macro conflfails end
macro errfails end
macro jl_callfails end
macro jl_deffails end
macro labelfails end
macro methfails end
macro mutfails end
macro netfails end
macro propfails end

end

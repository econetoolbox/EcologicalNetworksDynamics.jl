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
    EN, N, F, NetworkFramework, I, SparseMatrix, Display, errwith, withcontext
using .Display: rept, render_input, yellow, black, reset, italics
using .NetworkFramework: NF, D

using .Strings:
    showcompare,
    is_string, is_repr, is_disp,
    check_string, check_repr, check_disp, check_err,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors:
    @fails, @fails_with, @genfailsmacro, FieldsCompare, WrongField, test_errsource, errfield

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
@genfailsmacro jl_basic_callfails Base.MethodError (;
    f = nothing,
    args = nothing,
    world = nothing,
)

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
    using ..T: T, I, F, NF, @genfailsmacro, mess, rept, WrongField, italics, reset
    "The `node` fields on `AddError` is easily tested as a *path* of blueprint types."
    function node(exp, node; skip_first = false)
        exp isa Vector ||
            T.errwith("not a path vector to compare against a node", rethrow) do io
                println(io, rept(exp))
            end
        node isa F.Node || T.errwith(WrongField, "not an `add!` node", rethrow) do io
            println(io, rept(node))
        end
        act = F.path(node)
        if skip_first
            popfirst!(act)
        end
        err() = T.errwith(WrongField, "wrong nodes path", rethrow) do io
            if skip_first
                println(io, "  $italics(the first actual path step was skipped)$reset")
            end
            e = join(exp, ", ")
            a = join(act, ", ")
            T.showcompare(io, "[$e]", "[$a]") # (display vecs without leading type)
        end
        length(act) == length(exp) || err()
        for (e, a) in zip(exp, act)
            e === a || err()
        end
    end
    @genfailsmacro bpconflict F.ConflictWithBroughtComponent (; node, other_node = node)
    @genfailsmacro broughtalready F.BroughtAlreadyInValue (; node)
    @genfailsmacro component F.ComponentError (; mess)
    @genfailsmacro lower F.LoweringAborted (; node)
    @genfailsmacro missingrequired F.MissingRequiredComponent (; node)
    @genfailsmacro sysconflict F.ConflictWithSystemComponent (; node)
    # That one is more involved..
    @genfailsmacro check F.HookCheckFailure (;
        # ..because it's forwarding underlying library exception..
        err = T.errfield(NF.BlueprintError),
        # ..so this should always be redundant with the above's :early vs :late 'step':
        late = nothing,
        # .. and the first element in the path should always be redundant with BP type:
        node = (e, a) -> node(e, a; skip_first = true),
    )
    # Keep a simple one around to check the framework itself.
    @genfailsmacro check_raw F.HookCheckFailure (; node, err = (e, a) -> mess(e, a.mess))
end

#-------------------------------------------------------------------------------------------
# Exposed library errors.

"Test report ref values, using `:whole` to expect `$(NF.WholeData)`."
compare_refs(exp, act) = FieldsCompare.default(exp, act)
compare_refs(exp::Symbol, ::NF._WholeData) =
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

const checkrefs = (; uref = compare_refs, mref = compare_refs)
@genfailsmacro checkfails EN.NetworkFramework.CheckError (; mess, checkrefs...)
@genfailsmacro mutfails EN.NetworkFramework.MutationError

# This one is sometimes yielded as toplevel,
# and sometimes as a *cause* during addfails.check.
@genfailsmacro bpfails EN.NetworkFramework.BlueprintError

@genfailsmacro viewfails EN.NetworkFramework.Query.Error (; query = nothing)
#                                                           ^^^^^ (redundant with test lhs)

# Systematic redirection of `src` field testing for these type.
# (useful to have addfails.@check invocations correctly forward flow)
T.test_errsource(err, E::Type{NF.CheckError}, fields, checks = (;)) =
    @invoke T.test_errsource(err, E::Type, fields, (; checkrefs, checks...))

#-------------------------------------------------------------------------------------------
# (reassure JuliaLS)

macro aliasfails end
macro argfails end
macro bluefails end
macro bpfails end
macro callfails end
macro checkfails end
macro compfails end
macro conflfails end
macro errfails end
macro jl_basic_callfails end
macro jl_callfails end
macro jl_deffails end
macro labelfails end
macro methfails end
macro mutfails end
macro netfails end
macro propfails end
macro viewfails end

end

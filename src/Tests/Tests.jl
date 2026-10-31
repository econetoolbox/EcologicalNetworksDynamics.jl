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
# Symbols are not imported here only to be directly used here,
# but also to be imported from within tests modules.

const T = Tests

using EcologicalNetworksDynamics:
    EN, N, F, I, SparseMatrix, errwith, withcontext
using EcologicalNetworksDynamics.Display:
    rept, render_input, yellow, black, cyan, reset, italics
using EcologicalNetworksDynamics.NetworkFramework: NF, D, V

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
    using EcologicalNetworksDynamics.Framework: Component, CompType
    # (erroring here is always in the context of rethrowing from `catch`ing the checked err)
    reerrwith(args...; kwargs...) = T.errwith(args..., rethrow; kwargs...)
    "The `node` fields on `AddError` is easily tested as a *path* of blueprint types."
    function node(exp, node; skip_first = false)
        exp isa Vector ||
            reerrwith("not a path vector to compare against a node") do io
                println(io, rept(exp))
            end
        node isa F.Node || reerrwith(WrongField, "not an `add!` node") do io
            println(io, rept(node))
        end
        act = F.path(node)
        if skip_first
            popfirst!(act)
        end
        err() = reerrwith(WrongField, "wrong nodes path") do io
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
    "It is okay to use a component singleton to compare against the type."
    comp(exp, act) =
        exp === act || reerrwith(WrongField, "wrong component") do io
            T.showcompare(io, exp, act)
        end
    comp(exp::Component, act::CompType) = comp(typeof(exp), act)
    @genfailsmacro bpconflict F.ConflictWithBroughtComponent (; node, other_node = node)
    @genfailsmacro broughtalready F.BroughtAlreadyInValue (; node)
    @genfailsmacro component F.ComponentError (; mess)
    @genfailsmacro lower F.LoweringAborted (; node)
    @genfailsmacro missingrequired F.MissingRequiredComponent (;
        node, Miss = comp, Comp = comp)
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

"""
Test report ref values,
using `:u` and `:m` to refer to either `UserRef` or `ModelRef`,
and `:whole` to expect `$(NF.WholeData)`.
"""
function compare_refs((type, ref)::Tuple{Symbol,Any}, act)
    T = if type == :u
        NF.UserRef
    elseif type == :m
        NF.ModelRef
    else
        errwith("Invalid expected input reference qualifier:", rethrow) do io
            showcompare(io, "$cyan:u$reset (`UserRef`) or $cyan:r$reset (`ModelRef`)", type)
        end
    end
    if ref == :whole
        ref = NF.WholeData
    end
    FieldsCompare.default(T(ref), act)
end
"For convenience, use directly use `:uwhole` or `:mwhole`."
compare_refs(exp::Symbol, act) =
    if exp == :uwhole
        compare_refs((:u, :whole), act)
    elseif exp == :mwhole
        compare_refs((:m, :whole), act)
    else
        @invoke compare_refs(exp::Any, act)
    end
compare_refs(exp, _) =
    errwith("Invalid expected input reference qualifier:", rethrow) do io
        showcompare(io, "`(:u, ref)` or `(:m, ref)` or `:uwhole` or `:mwhole`", exp)
    end

"Test datakind/dispatcher value, using tuples of symbols for their content."
test_datakind(exp, ::D.Dispatcher) =
    errwith("Not a tuple of symbols to compare against data kind:", rethrow) do io
        showcompare(io, "data kind spec like (:class, :field)", exp)
    end
test_datakind(exp::Tuple{Vararg{Symbol}}, act::D.Dispatcher) =
    FieldsCompare.value(exp, D.content(act))

const ref = compare_refs
@genfailsmacro convfails NF.ConvertError (; mess, ref)
@genfailsmacro listfails NF.ListError (;
    mess, tag = nothing, path = FieldsCompare.value)
@genfailsmacro checkfails NF.CheckError (; mess, ref)

const src = T.errfield(NF.CheckError)
@genfailsmacro bpfails NF.BlueprintError (; src)
@genfailsmacro mutfails NF.MutationError (; src)

@genfailsmacro viewfails NF.Views.Error (; src, query = nothing)
#                                               ^^^^^ (redundant with test lhs)
@genfailsmacro immutfails NF.Views.ImmutableError

# Systematic redirection of `src` field testing for these type.
# (useful to have addfails.@check invocations correctly forward flow)
T.test_errsource(err, E::Type{NF.CheckError}, fields, checks = (;)) =
    @invoke T.test_errsource(err, E::Type, fields, (; mess, ref, checks...))
T.test_errsource(err, E::Type{NF.BlueprintError}, fields, checks = (;)) =
    @invoke T.test_errsource(err, E::Type, fields,
        (; src = T.errfield(NF.CheckError), checks...))

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
macro convfails end
macro errfails end
macro immutfails end
macro jl_basic_callfails end
macro jl_callfails end
macro jl_deffails end
macro labelfails end
macro listfails end
macro methfails end
macro mutfails end
macro netfails end
macro propfails end
macro viewfails end

end

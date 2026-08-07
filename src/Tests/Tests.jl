"""
Testing utils.
Not useful for end users, but heavily used in package automated testing
and useful to setup development environment with Revise for contributors.
"""
module Tests

include("./strings.jl")
include("./errors.jl")

# ==========================================================================================
# Exposed testing interface, with the collection of macros directly used in tests.

const T = Tests

using EcologicalNetworksDynamics: EN, F, I, SparseMatrix

using .Strings:
    is_string, is_repr, is_disp,
    check_string, check_repr, check_disp, check_err,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors: @fails, @fails_with, @genfailsmacro, FieldsCompare

# Native julia exceptions.
@genfailsmacro jl_deffails Base.UndefVarError (; world = nothing)
@genfailsmacro jl_methfails Base.MethodError (; world = nothing)

"""
Numerous exception types in the package have a `mess` field
to be tested as an error message.
"""
const mess = FieldsCompare.message

# Network errors.
@genfailsmacro netfails EN.Networks.NetworkError
@genfailsmacro labelfails EN.Networks.LabelError (; index = nothing)

#-------------------------------------------------------------------------------------------
# Framework errors.

"Generate macros for framework exceptions parametrized with the given `Value` type."
macro gen_framework_fails(Value)
    quote
        $T.@genfailsmacro propfails $F.PropertyError{$F.System{$Value}}
        $T.@genfailsmacro methfails $F.MethodError{$Value}
    end |> esc
end
@genfailsmacro conflfails F.ConflictError (; mess)

"Generate macros for failures in defining items."
macro genitemfailsfor(itemtype, name)
    itemtype = QuoteNode(itemtype)
    quote
        macro $name(xp, f...)
            src = $(esc(:__source__)) # (https://github.com/JuliaLang/julia/issues/62572)
            mcall = :($($T).@itemfails($xp, $($itemtype), $(f...)))
            mcall.args[2] = src
            esc(mcall)
        end
    end
end
@genfailsmacro itemfails F.ItemError (; mess)
@genitemfailsfor :blueprint bluefails
@genitemfailsfor :component compfails

# (reassure JuliaLS)
macro jl_deffails end
macro jl_methfails end
macro netfails end
macro labelfails end
macro bluefails end
macro compfails end
macro conflfails end

"Test various possible failures during `Framework.add!()`."
module addfails
    using ..T: T, I, F, @genfailsmacro, mess
    "The `node` fields on `AddError` is easily tested as a *path* of blueprint types."
    function node(exp::Vector, node::F.Node)
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
    @genfailsmacro hookcheck F.HookCheckFailure (; node)
    @genfailsmacro missingrequired F.MissingRequiredComponent (; node)
    @genfailsmacro sysconflict F.ConflictWithSystemComponent (; node)
end

end

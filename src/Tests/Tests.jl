"""
Testing utils.
Not useful for end users, but heavily used in package automated testing
and useful to setup development environment with Revise for contributors.
"""
module Tests

include("./strings.jl")
include("./errors.jl")

#-------------------------------------------------------------------------------------------
# Exposed testing interface.

const T = Tests

using EcologicalNetworksDynamics: EN, F, I, SparseMatrix

using .Strings:
    is_string, is_repr, is_disp,
    check_string, check_repr, check_disp, check_err,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors: @fails, @fails_with, @genfailsmacro, FieldsCompare

# The collection of macros directly used in tests.
@genfailsmacro deffails UndefVarError (; world = nothing)
@genfailsmacro netfails EN.Networks.NetworkError
@genfailsmacro labelfails EN.Networks.LabelError (; index = nothing)
# (reassure JuliaLS)
macro deffails end
macro netfails end
macro labelfails end

"Typical error message string field-checking."
const mess = FieldsCompare.message

"Generate macros for framework exception, given a parameter `Value` type."
macro gen_framework_fails(Value)
    quote
        @genfailsmacro propfails $F.PropertyError{$F.System{$Value}}
        @genfailsmacro methfails $F.MethodError{$Value}
    end |> esc
end
@genfailsmacro itemfails F.ItemError

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
    @genfailsmacro broughtalready F.BroughtAlreadyInValue (; node)
    @genfailsmacro component F.ComponentError (; mess)
    @genfailsmacro conflict F.ConflictWithSystemComponent (; node)
    @genfailsmacro hookcheck F.HookCheckFailure (; node)
    @genfailsmacro missingrequired F.MissingRequiredComponent (; node)
    # (reassure JuliaLS)
    macro broughtalready end
    macro hookcheck end
    macro missingrequired end
    macro conflict end
end

end
